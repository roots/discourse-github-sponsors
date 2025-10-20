# frozen_string_literal: true

class DiscordBotTokenValidator
  def initialize(opts = {})
    @opts = opts
  end

  def valid_value?(val)
    return true if val.blank? # Allow empty to disable the feature

    # Discord bot tokens have three parts separated by dots
    # Format: MTk4NjIyNDgzNDcxOTI1MjQ4.Cl2FMQ.ZnCjm1XVW7vRze4b7Cq4se7lk
    # Part 1: Base64 encoded bot user ID
    # Part 2: Timestamp
    # Part 3: HMAC signature
    parts = val.split(".")
    return false unless parts.length == 3

    # Basic length validation (tokens are usually 50-100 characters)
    return false if val.length < 50 || val.length > 100

    # Validate parts contain valid base64-like characters
    parts.all? { |part| part.match?(/^[A-Za-z0-9_-]+$/) }
  end

  def error_message
    I18n.t("site_settings.errors.discord_bot_token_invalid")
  end
end
