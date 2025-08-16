# frozen_string_literal: true

# == Schema Information
#
# Table name: github_sponsor_sync_histories
#
#  id                 :bigint           not null, primary key
#  added_users        :integer          default(0)
#  details            :json
#  error_message      :text
#  matched_sponsors   :integer          default(0)
#  removed_users      :integer          default(0)
#  success            :boolean          default(TRUE)
#  synced_at          :datetime         not null
#  total_sponsors     :integer          default(0)
#  unmatched_sponsors :integer          default(0)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_github_sponsor_sync_histories_on_success                (success)
#  index_github_sponsor_sync_histories_on_synced_at              (synced_at)
#  index_github_sponsor_sync_histories_on_synced_at_and_success  (synced_at,success)
#

class GithubSponsorSyncHistory < ActiveRecord::Base
  self.table_name = "github_sponsor_sync_histories"

  scope :recent, -> { order(synced_at: :desc).limit(10) }
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }

  def self.log_sync(result, error_message = nil)
    create!(
      synced_at: Time.current,
      total_sponsors: result[:total_sponsors] || 0,
      matched_sponsors: result[:matched_sponsors]&.length || 0,
      unmatched_sponsors: result[:unmatched_sponsors]&.length || 0,
      added_users: result[:added_users]&.length || 0,
      removed_users: result[:removed_users]&.length || 0,
      success: error_message.nil?,
      error_message: error_message,
      details: result.slice(:sponsor_usernames, :added_users, :removed_users),
    )
  end

  # Clean up old history entries based on retention setting
  def self.cleanup_old_entries(retention_days = nil)
    retention_days ||= SiteSetting.github_sponsors_sync_history_retention_days
    cutoff_date = retention_days.days.ago
    
    records_to_delete = where("synced_at < ?", cutoff_date)
    deleted_count = records_to_delete.count
    records_to_delete.destroy_all
    
    Rails.logger.info("GitHub Sponsors: Cleaned up #{deleted_count} sync history records older than #{retention_days} days") if deleted_count > 0
    deleted_count
  end
end

