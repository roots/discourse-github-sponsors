# frozen_string_literal: true

module DiscourseGithubSponsors
  class DiscordController < ::ApplicationController
    requires_plugin DiscourseGithubSponsors::PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_sponsor, only: %i[status generate_invite]
    before_action :ensure_discord_configured, only: %i[status generate_invite]

    def status
      discord_account = get_user_discord_account

      unless discord_account
        render json: { has_discord_linked: false, on_server: false, discord_username: nil }
        return
      end

      # Discord stores username in the info hash
      discord_username = discord_account.info["username"] || discord_account.info["name"]

      # Check if user is on the Discord server
      api = DiscourseGithubSponsors::DiscordApi.new
      on_server = api.member_exists?(discord_username)

      render json: {
               has_discord_linked: true,
               on_server: on_server,
               discord_username: discord_username,
             }
    rescue => e
      Rails.logger.error("Discord status check error: #{e.message}")
      render json: {
               error: "Failed to check Discord status",
               has_discord_linked: true,
             },
             status: 500
    end

    def generate_invite
      discord_account = get_user_discord_account

      unless discord_account
        render json: { error: I18n.t("github_sponsors.errors.discord_not_linked") }, status: 422
        return
      end

      discord_username = discord_account.info["username"] || discord_account.info["name"]

      # Check if user is already on server
      api = DiscourseGithubSponsors::DiscordApi.new
      if api.member_exists?(discord_username)
        render json: { error: I18n.t("github_sponsors.errors.already_on_server") }, status: 422
        return
      end

      # Generate the invite
      invite_code = api.create_invite

      # Send webhook notification
      github_account =
        UserAssociatedAccount.find_by(user_id: current_user.id, provider_name: "github")
      github_username = github_account&.info&.dig("nickname") || current_user.username

      api.send_webhook_notification(
        "#{github_username} generated a Discord invite (Discord: #{discord_username})",
      )

      # Log the invite generation
      expires_at = Time.now + SiteSetting.discord_invite_max_age
      DiscordInviteLog.log_invite(
        user: current_user,
        invite_code: invite_code,
        discord_username: discord_username,
        github_username: github_username,
        expires_at: expires_at,
      )

      render json: {
               invite_code: invite_code,
               invite_url: "https://discord.gg/#{invite_code}",
               expires_at: expires_at.to_i,
             }
    rescue DiscourseGithubSponsors::DiscordApi::PermissionError => e
      Rails.logger.error("Discord permission error: #{e.message}")
      render json: { error: I18n.t("github_sponsors.errors.bot_permission") }, status: 500
    rescue DiscourseGithubSponsors::DiscordApi::RateLimitError => e
      Rails.logger.error("Discord rate limit: #{e.message}")
      render json: { error: I18n.t("github_sponsors.errors.rate_limited") }, status: 429
    rescue => e
      Rails.logger.error("Discord invite generation error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: I18n.t("github_sponsors.errors.api_error") }, status: 500
    end

    private

    def ensure_sponsor
      sponsor_group = Group.find_by(name: SiteSetting.github_sponsors_group_name)
      unless sponsor_group&.users&.include?(current_user)
        render json: { error: I18n.t("github_sponsors.errors.not_sponsor") }, status: 403
      end
    end

    def ensure_discord_configured
      if SiteSetting.discord_server_guild_id.blank? || SiteSetting.discord_bot_token.blank?
        render json: { error: "Discord is not configured" }, status: 422
      end
    end

    def get_user_discord_account
      UserAssociatedAccount
        .where(user_id: current_user.id)
        .where("LOWER(provider_name) = ?", "discord")
        .first
    end
  end
end
