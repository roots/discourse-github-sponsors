# frozen_string_literal: true

class DiscordChannelIdValidator
  def initialize(opts = {})
    @opts = opts
  end

  def valid_value?(val)
    return true if val.blank? # Allow empty to disable the feature

    # Discord snowflake IDs are 17-19 digit numbers
    val.match?(/^\d{17,19}$/)
  end

  def error_message
    I18n.t("site_settings.errors.discord_channel_id_invalid")
  end
end
