# frozen_string_literal: true

class GithubAccountValidator
  def initialize(opts = {})
    @opts = opts
  end

  def valid_value?(val)
    return true if val.blank? # Allow empty to disable the plugin

    # GitHub usernames can contain alphanumeric characters and hyphens
    # Cannot start with hyphen, and cannot have consecutive hyphens
    # Max length is 39 characters
    return false unless val.match?(/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$/)
    return false if val.include?("--")

    true
  end

  def error_message
    I18n.t("site_settings.errors.github_account_invalid")
  end
end
