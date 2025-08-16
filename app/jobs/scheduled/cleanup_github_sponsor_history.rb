# frozen_string_literal: true

module ::Jobs
  class CleanupGithubSponsorHistory < ::Jobs::Scheduled
    every 1.day
    sidekiq_options retry: false

    def execute(args)
      return unless SiteSetting.github_sponsors_enabled

      deleted_count = ::GithubSponsorSyncHistory.cleanup_old_entries
      
      Rails.logger.info("GitHub Sponsors: Daily cleanup completed, removed #{deleted_count} old records") if deleted_count > 0
    end
  end
end