# frozen_string_literal: true

class DiscordWebhookValidator
  def initialize(opts = {})
    @opts = opts
  end

  def valid_value?(val)
    return true if val.blank? # Allow empty (webhook is optional)

    # Discord webhook URLs format:
    # https://discord.com/api/webhooks/{webhook.id}/{webhook.token}
    # or https://discordapp.com/api/webhooks/{webhook.id}/{webhook.token}
    val.match?(%r{^https://(discord|discordapp)\.com/api/webhooks/\d{17,19}/[A-Za-z0-9_-]+$})
  end

  def error_message
    I18n.t("site_settings.errors.discord_webhook_url_invalid")
  end
end
