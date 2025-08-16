# frozen_string_literal: true

class GithubTokenValidator
  def initialize(opts = {})
    @opts = opts
  end

  def valid_value?(val)
    return true if val.blank? # Allow empty to disable the plugin

    # GitHub personal access tokens start with ghp_ (new format) or are 40 hex chars (old format)
    return false unless val.match?(/^ghp_[a-zA-Z0-9]{36}$/) || val.match?(/^[a-f0-9]{40}$/)

    # Optionally validate the token has required scopes
    if @opts[:validate_scopes] && val.present?
      validate_token_scopes(val)
    else
      true
    end
  end

  def error_message
    I18n.t("site_settings.errors.github_token_invalid")
  end

  private

  def validate_token_scopes(token)
    # Make a simple API call to validate the token and check scopes
    begin
      response =
        Faraday.get(
          "https://api.github.com/user",
          {},
          { "Authorization" => "Bearer #{token}", "Accept" => "application/vnd.github.v3+json" },
        )

      if response.success?
        scopes = response.headers["x-oauth-scopes"]&.split(", ") || []
        required_scopes = %w[read:org read:user user:email]

        missing_scopes = required_scopes - scopes
        if missing_scopes.any?
          @error_details = "Missing required scopes: #{missing_scopes.join(", ")}"
          return false
        end

        true
      else
        @error_details = "Invalid token: #{response.status}"
        false
      end
    rescue => e
      @error_details = "Error validating token: #{e.message}"
      false
    end
  end
end
