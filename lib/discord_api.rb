# frozen_string_literal: true

module DiscourseGithubSponsors
  class DiscordApi
    class ApiError < StandardError
    end
    class RateLimitError < StandardError
    end
    class PermissionError < StandardError
    end

    DISCORD_API_BASE = "https://discord.com/api/v10"
    USER_AGENT = "Discourse-GitHub-Sponsors/1.0"
    CACHE_TTL = 5.minutes

    def initialize
      @bot_token = SiteSetting.discord_bot_token
      @rate_limit_remaining = nil
      @rate_limit_reset = nil
    end

    # Search for a member in the guild by username
    # Returns true if found, false otherwise
    def member_exists?(username)
      guild_id = SiteSetting.discord_server_guild_id
      return false if guild_id.blank? || username.blank?

      # Check cache first
      cache_key = "discord_member_#{guild_id}_#{username.downcase}"
      cached = get_cached(cache_key)
      return cached if cached.is_a?(TrueClass) || cached.is_a?(FalseClass)

      check_rate_limit!

      response =
        make_request(
          :get,
          "/guilds/#{guild_id}/members/search?query=#{CGI.escape(username)}&limit=1",
        )

      update_rate_limit_info(response)

      unless response.success?
        handle_error_response(response)
        return false
      end

      result = JSON.parse(response.body)
      found = result.is_a?(Array) && result.any?

      # Cache the result
      set_cached(cache_key, found, CACHE_TTL)

      found
    rescue JSON::ParserError => e
      Rails.logger.error("Discord API: Invalid JSON response - #{e.message}")
      false
    rescue ApiError => e
      Rails.logger.error("Discord API error: #{e.message}")
      false
    end

    # Create a single-use invite for a channel
    # Returns the invite code or raises an error
    def create_invite(channel_id = nil)
      channel_id ||= SiteSetting.discord_invite_channel_id
      raise ApiError, "No Discord channel ID configured" if channel_id.blank?

      check_rate_limit!

      max_age = SiteSetting.discord_invite_max_age || 3600

      response =
        make_request(
          :post,
          "/channels/#{channel_id}/invites",
          { max_age: max_age, max_uses: 1 }.to_json,
        )

      update_rate_limit_info(response)

      handle_error_response(response) unless response.success?

      result = JSON.parse(response.body)

      raise ApiError, "Discord API did not return an invite code" unless result["code"]

      result["code"]
    rescue JSON::ParserError => e
      raise ApiError, "Invalid JSON response: #{e.message}"
    end

    # Send a notification to the configured webhook
    def send_webhook_notification(content)
      webhook_url = SiteSetting.discord_webhook_url
      return false if webhook_url.blank?

      begin
        response =
          Faraday.post(
            webhook_url,
            { content: content }.to_json,
            { "Content-Type" => "application/json", "User-Agent" => USER_AGENT },
          ) { |req| req.options.timeout = 10 }

        response.success?
      rescue => e
        Rails.logger.error("Discord webhook error: #{e.message}")
        false
      end
    end

    # Get rate limit status
    def rate_limit_status
      {
        remaining: @rate_limit_remaining,
        reset_at: @rate_limit_reset ? Time.at(@rate_limit_reset) : nil,
        reset_in: @rate_limit_reset ? [@rate_limit_reset - Time.now.to_i, 0].max : nil,
      }
    end

    private

    def make_request(method, path, body = nil)
      url = "#{DISCORD_API_BASE}#{path}"

      headers = {
        "Authorization" => "Bot #{@bot_token}",
        "User-Agent" => USER_AGENT,
        "Content-Type" => "application/json",
      }

      case method
      when :get
        Faraday.get(url, nil, headers) do |req|
          req.options.timeout = 30
          req.options.open_timeout = 10
        end
      when :post
        Faraday.post(url, body, headers) do |req|
          req.options.timeout = 30
          req.options.open_timeout = 10
        end
      else
        raise ArgumentError, "Unsupported HTTP method: #{method}"
      end
    rescue Faraday::TimeoutError => e
      raise ApiError, "Request timeout: #{e.message}"
    rescue Faraday::ConnectionFailed => e
      raise ApiError, "Connection failed: #{e.message}"
    end

    def update_rate_limit_info(response)
      if response.headers["x-ratelimit-remaining"]
        @rate_limit_remaining = response.headers["x-ratelimit-remaining"].to_i
        @rate_limit_reset = response.headers["x-ratelimit-reset"].to_f

        if @rate_limit_remaining && @rate_limit_remaining < 10
          Rails.logger.warn("Discord API rate limit low: #{@rate_limit_remaining} remaining")
        end
      end
    end

    def check_rate_limit!
      if @rate_limit_remaining && @rate_limit_remaining <= 0
        if @rate_limit_reset
          wait_time = @rate_limit_reset - Time.now.to_f
          if wait_time > 0 && wait_time < 60
            Rails.logger.info("Rate limited. Waiting #{wait_time.round(2)} seconds...")
            sleep(wait_time + 0.5)
            @rate_limit_remaining = nil
          else
            raise RateLimitError,
                  "Discord API rate limit exceeded. Resets at #{Time.at(@rate_limit_reset)}"
          end
        else
          raise RateLimitError, "Discord API rate limit exceeded"
        end
      end
    end

    def handle_error_response(response)
      error_message = "Discord API error: #{response.status}"

      begin
        body = JSON.parse(response.body)
        error_message = "Discord API: #{body["message"]}" if body["message"]
      rescue JSON::ParserError
        # Use status code error message
      end

      case response.status
      when 401
        raise ApiError, "Invalid Discord bot token (401 Unauthorized)"
      when 403
        if response.headers["x-ratelimit-remaining"] == "0"
          raise RateLimitError, "Discord API rate limit exceeded"
        else
          raise PermissionError, "Bot lacks required permissions (403 Forbidden): #{error_message}"
        end
      when 404
        raise ApiError, "Discord resource not found (404) - Check guild/channel IDs"
      when 429
        raise RateLimitError, "Discord API rate limit exceeded (429)"
      when 500..599
        raise ApiError, "Discord server error (#{response.status})"
      else
        raise ApiError, error_message
      end
    end

    def get_cached(key)
      cached = ::DiscourseGithubSponsors.store.get("discord_#{key}")
      return nil unless cached

      if cached[:expires_at] && cached[:expires_at] < Time.now.to_i
        ::DiscourseGithubSponsors.store.remove("discord_#{key}")
        return nil
      end

      cached[:data]
    end

    def set_cached(key, data, ttl)
      ::DiscourseGithubSponsors.store.set(
        "discord_#{key}",
        { data: data, expires_at: Time.now.to_i + ttl.to_i },
      )
    end
  end
end
