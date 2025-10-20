# frozen_string_literal: true

module DiscourseGithubSponsors
  class AdminController < ::Admin::AdminController
    requires_plugin DiscourseGithubSponsors::PLUGIN_NAME

    before_action :ensure_github_sponsors_enabled
    before_action :ensure_github_credentials_present, only: [:sync]

    def index
      sponsors_group = Group.find_by(name: SiteSetting.github_sponsors_group_name)
      github_users = UserAssociatedAccount.where(provider_name: "github")

      sponsors =
        github_users
          .select { |account| sponsors_group && sponsors_group.users.exists?(account.user_id) }
          .map do |account|
            {
              id: account.user.id,
              username: account.user.username,
              github_username: account.info["nickname"],
            }
          end

      # Get rate limit status
      api = ::DiscourseGithubSponsors::Api.new
      rate_limit = api.rate_limit_status

      render json: {
               sponsors: sponsors,
               github_sponsors_enabled: SiteSetting.github_sponsors_enabled,
               rate_limit: rate_limit,
             }
    end

    def history
      history =
        GithubSponsorSyncHistory.recent.map do |entry|
          {
            synced_at: entry.synced_at,
            total_sponsors: entry.total_sponsors,
            matched_sponsors: entry.matched_sponsors,
            unmatched_sponsors: entry.unmatched_sponsors,
            added_users: entry.added_users,
            removed_users: entry.removed_users,
            success: entry.success,
            error_message: entry.error_message,
          }
        end

      render json: { history: history }
    end

    def discord_invites
      invites =
        DiscordInviteLog
          .recent
          .includes(:user)
          .map do |invite|
            {
              id: invite.id,
              user_id: invite.user_id,
              username: invite.user.username,
              github_username: invite.github_username,
              discord_username: invite.discord_username,
              invite_code: invite.invite_code,
              created_at: invite.created_at,
              expires_at: invite.expires_at,
              used_at: invite.used_at,
              expired: invite.expired?,
              status: invite.status,
            }
          end

      # Calculate statistics
      total_invites = DiscordInviteLog.count
      used_invites = DiscordInviteLog.used.count
      expired_invites = DiscordInviteLog.where("expires_at < ?", Time.current).count
      active_invites = DiscordInviteLog.where("expires_at >= ?", Time.current).unused.count

      render json: {
               invites: invites,
               stats: {
                 total: total_invites,
                 used: used_invites,
                 expired: expired_invites,
                 active: active_invites,
                 usage_rate:
                   total_invites > 0 ? ((used_invites.to_f / total_invites) * 100).round(1) : 0,
               },
             }
    end

    def sync
      begin
        result = ::DiscourseGithubSponsors::Sync.new.perform

        if result[:error]
          ::GithubSponsorSyncHistory.log_sync(result, result[:error])
        else
          ::GithubSponsorSyncHistory.log_sync(result)
        end

        render json: result
      rescue => e
        Rails.logger.error "GitHub Sponsors sync error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        begin
          GithubSponsorSyncHistory.log_sync({}, e.message)
        rescue => log_error
          Rails.logger.error("Failed to log sync error: #{log_error.message}")
        end

        render json: {
                 error: e.message,
                 backtrace: e.backtrace.first(10),
                 class: e.class.name,
               },
               status: 500
      end
    end

    private

    def ensure_github_sponsors_enabled
      unless SiteSetting.github_sponsors_enabled
        render json: { error: I18n.t("github_sponsors.errors.plugin_disabled") }, status: 403
      end
    end

    def ensure_github_credentials_present
      if SiteSetting.github_sponsors_token.blank?
        render json: { error: I18n.t("github_sponsors.errors.no_token") }, status: 422
        return
      end

      if SiteSetting.github_sponsors_account.blank?
        render json: { error: I18n.t("github_sponsors.errors.no_account") }, status: 422
        nil
      end
    end
  end
end
