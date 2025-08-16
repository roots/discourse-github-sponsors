# frozen_string_literal: true

module DiscourseGithubSponsors
  class Api
    class RateLimitError < StandardError
    end
    class ApiError < StandardError
    end

    GITHUB_API_URL = "https://api.github.com/graphql"
    USER_AGENT = "Discourse-GitHub-Sponsors/1.0"
    CACHE_TTL = 5.minutes

    def initialize(token = nil)
      @token = token || SiteSetting.github_sponsors_token
      @rate_limit_remaining = nil
      @rate_limit_reset = nil
    end

    def query(graphql_query, cache_key: nil, cache_ttl: CACHE_TTL)
      # Try to get from cache if cache_key provided
      if cache_key
        cached_result = get_cached(cache_key)
        return cached_result if cached_result
      end

      check_rate_limit!

      response = make_request(graphql_query)

      update_rate_limit_info(response)

      handle_error_response(response) unless response.success?

      result = JSON.parse(response.body)
      
      # Check for GraphQL errors
      if result["errors"]
        error_messages = result["errors"].map { |e| e["message"] }.join(", ")
        raise ApiError, "GitHub API error: #{error_messages}"
      end

      # Cache successful responses
      if cache_key && result && !result["errors"]
        set_cached(cache_key, result, cache_ttl)
      end

      result
    rescue JSON::ParserError => e
      raise ApiError, "Invalid JSON response: #{e.message}"
    end

    def rate_limit_status
      # If we don't have rate limit info, fetch it
      if @rate_limit_remaining.nil?
        fetch_rate_limit_status
      end
      
      {
        remaining: @rate_limit_remaining,
        reset_at: @rate_limit_reset ? Time.at(@rate_limit_reset) : nil,
        reset_in: @rate_limit_reset ? [@rate_limit_reset - Time.now.to_i, 0].max : nil,
      }
    end

    private

    def make_request(query)
      Faraday.post(
        GITHUB_API_URL,
        { query: query }.to_json,
        {
          "Authorization" => "Bearer #{@token}",
          "Content-Type" => "application/json",
          "User-Agent" => USER_AGENT,
          "Accept" => "application/vnd.github.v3+json",
        },
      ) do |req|
        req.options.timeout = 30
        req.options.open_timeout = 10
      end
    rescue Faraday::TimeoutError => e
      raise ApiError, "Request timeout: #{e.message}"
    rescue Faraday::ConnectionFailed => e
      raise ApiError, "Connection failed: #{e.message}"
    end

    def update_rate_limit_info(response)
      # GitHub returns rate limit info in headers
      if response.headers["x-ratelimit-remaining"]
        @rate_limit_remaining = response.headers["x-ratelimit-remaining"].to_i
        @rate_limit_reset = response.headers["x-ratelimit-reset"].to_i

        # Log warning if we're getting low on API calls
        if @rate_limit_remaining && @rate_limit_remaining < 100
          Rails.logger.warn("GitHub API rate limit low: #{@rate_limit_remaining} remaining")
        end
      end

      # Also check for rate limit in GraphQL response
      if response.success?
        data =
          begin
            JSON.parse(response.body)
          rescue StandardError
            {}
          end
        if data.dig("data", "rateLimit")
          rate_limit = data["data"]["rateLimit"]
          @rate_limit_remaining = rate_limit["remaining"]
          @rate_limit_reset = Time.parse(rate_limit["resetAt"]).to_i
        end
      end
    end

    def check_rate_limit!
      # If we know we're rate limited, wait or raise error
      if @rate_limit_remaining && @rate_limit_remaining <= 0
        if @rate_limit_reset
          wait_time = @rate_limit_reset - Time.now.to_i
          if wait_time > 0 && wait_time < 60
            # If we need to wait less than a minute, just wait
            Rails.logger.info("Rate limited. Waiting #{wait_time} seconds...")
            sleep(wait_time + 1)
            @rate_limit_remaining = nil # Reset so we try again
          else
            raise RateLimitError,
                  "GitHub API rate limit exceeded. Resets at #{Time.at(@rate_limit_reset)}"
          end
        else
          raise RateLimitError, "GitHub API rate limit exceeded"
        end
      end
    end

    def handle_error_response(response)
      error_message = "GitHub API error: #{response.status}"

      begin
        body = JSON.parse(response.body)
        if body["message"]
          error_message = "GitHub API: #{body["message"]}"
        elsif body["errors"]
          errors = body["errors"].map { |e| e["message"] }.join(", ")
          error_message = "GitHub API: #{errors}"
        end
      rescue JSON::ParserError
        # Use status code error message
      end

      case response.status
      when 401
        ProblemCheckTracker[:github_token_invalid].problem!
        raise ApiError, "Invalid GitHub token (401 Unauthorized)"
      when 403
        if response.headers["x-ratelimit-remaining"] == "0"
          raise RateLimitError, "GitHub API rate limit exceeded"
        else
          raise ApiError, "Access forbidden (403): #{error_message}"
        end
      when 404
        raise ApiError, "GitHub resource not found (404)"
      when 422
        raise ApiError, "Invalid request (422): #{error_message}"
      when 500..599
        raise ApiError, "GitHub server error (#{response.status})"
      else
        raise ApiError, error_message
      end
    end

    def get_cached(key)
      cached = ::DiscourseGithubSponsors.store.get("cache_#{key}")
      return nil unless cached

      # Check if cache has expired
      if cached[:expires_at] && cached[:expires_at] < Time.now.to_i
        ::DiscourseGithubSponsors.store.remove("cache_#{key}")
        return nil
      end

      cached[:data]
    end

    def set_cached(key, data, ttl)
      ::DiscourseGithubSponsors.store.set(
        "cache_#{key}",
        { data: data, expires_at: Time.now.to_i + ttl.to_i },
      )
    end

    def clear_cache
      # Clear all cached items for this plugin
      # Note: PluginStore doesn't have a clear_all method, so we'd need to track keys
      # For now, this is a placeholder for future implementation
      Rails.logger.info("Cache clear requested for GitHub Sponsors plugin")
    end
    
    def fetch_rate_limit_status
      # Simple query to get rate limit info
      query = <<~GQL
        query {
          rateLimit {
            remaining
            resetAt
          }
        }
      GQL
      
      begin
        response = make_request(query)
        update_rate_limit_info(response)
        
        if response.success?
          data = JSON.parse(response.body)
          if data.dig("data", "rateLimit")
            rate_limit = data["data"]["rateLimit"]
            @rate_limit_remaining = rate_limit["remaining"]
            @rate_limit_reset = Time.parse(rate_limit["resetAt"]).to_i
          end
        end
      rescue => e
        Rails.logger.warn("Could not fetch rate limit status: #{e.message}")
      end
    end
  end
end
