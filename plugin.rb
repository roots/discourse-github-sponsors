# frozen_string_literal: true

# name: discourse-github-sponsors
# about: Syncs GitHub sponsor status with a Discourse group
# version: 0.0.1
# authors: Ben Word
# url: https://github.com/roots/discourse-github-sponsors
# required_version: 2.7.0

enabled_site_setting :github_sponsors_enabled

# Load validators before initialize
require_relative "lib/validators/github_token_validator"
require_relative "lib/validators/github_account_validator"
require_relative "lib/validators/discord_guild_id_validator"
require_relative "lib/validators/discord_channel_id_validator"
require_relative "lib/validators/discord_bot_token_validator"
require_relative "lib/validators/discord_webhook_validator"

require_relative "lib/engine"

after_initialize do
  require_dependency "admin_constraint"
  require "faraday"

  # Load lib files
  require_relative "lib/api"
  require_relative "lib/seed"
  require_relative "lib/sync"
  require_relative "lib/discord_api"

  # Load jobs
  require_relative "app/jobs/scheduled/github_sponsors_sync"

  # Load problem checks
  require_relative "app/services/problem_check/github_token_invalid"

  # Register problem check
  register_problem_check ProblemCheck::GithubTokenInvalid

  # Create/update the badge on plugin initialization
  on(:site_setting_changed) do |name, old_value, new_value|
    if name == :github_sponsors_enabled && new_value == true
      DiscourseGithubSponsors::Seed.create_badge!
    end
  end

  # Create badge if plugin is already enabled
  if SiteSetting.github_sponsors_enabled
    begin
      DiscourseGithubSponsors::Seed.create_badge!
    rescue => e
      Rails.logger.error "Failed to create GitHub Sponsor badge: #{e.message}"
    end
  end

  Discourse::Application.routes.append do
    get "/admin/plugins/github-sponsors/sponsors" => "discourse_github_sponsors/admin#index",
        :constraints => AdminConstraint.new
    get "/admin/plugins/github-sponsors/history" => "discourse_github_sponsors/admin#history",
        :constraints => AdminConstraint.new
    post "/admin/plugins/github-sponsors/sync" => "discourse_github_sponsors/admin#sync",
         :constraints => AdminConstraint.new
    get "/sponsors/status" => "discourse_github_sponsors/user_status#show"
    get "/sponsors/discord/status" => "discourse_github_sponsors/discord#status"
    post "/sponsors/discord/invite" => "discourse_github_sponsors/discord#generate_invite"
  end

  add_admin_route "github_sponsors.title", "github-sponsors"
end
