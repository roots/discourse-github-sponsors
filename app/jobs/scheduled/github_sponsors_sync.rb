# frozen_string_literal: true

module ::Jobs
  class GithubSponsorsSync < ::Jobs::Scheduled
    every 6.hours
    sidekiq_options retry: false

    def execute(args)
      return unless SiteSetting.github_sponsors_enabled

      Rails.logger.info("Starting GitHub sponsors sync")

      result = ::DiscourseGithubSponsors::Sync.new.perform
      
      if result[:error]
        Rails.logger.error("GitHub sponsors sync failed: #{result[:error]}")
        ::GithubSponsorSyncHistory.log_sync(result, result[:error])
        return result
      end

      ::GithubSponsorSyncHistory.log_sync(result)
      
      ::GithubSponsorSyncHistory.cleanup_old_entries

      Rails.logger.info(
        "GitHub sponsors sync completed: #{result[:matched_sponsors]&.length || 0} matched, #{result[:unmatched_sponsors]&.length || 0} unmatched",
      )

      result
    rescue => e
      Rails.logger.error("GitHub sponsors sync failed: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      ::GithubSponsorSyncHistory.log_sync({}, e.message)

      { error: e.message }
    end
  end
end
