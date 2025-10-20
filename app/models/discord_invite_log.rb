# frozen_string_literal: true

# == Schema Information
#
# Table name: discourse_github_sponsors_discord_invite_logs
#
#  id               :bigint           not null, primary key
#  discord_username :string(255)      not null
#  expired          :boolean          default(FALSE), not null
#  expires_at       :datetime         not null
#  github_username  :string(255)
#  invite_code      :string(50)       not null
#  used_at          :datetime
#  created_at       :datetime         not null
#  user_id          :integer          not null
#
# Indexes
#
#  idx_discord_invites_code        (invite_code) UNIQUE
#  idx_discord_invites_created_at  (created_at)
#  idx_discord_invites_user_id     (user_id)
#

class DiscordInviteLog < ActiveRecord::Base
  self.table_name = "discourse_github_sponsors_discord_invite_logs"

  belongs_to :user

  scope :recent, -> { order(created_at: :desc).limit(50) }
  scope :expired, -> { where(expired: true) }
  scope :unexpired, -> { where(expired: false) }
  scope :used, -> { where.not(used_at: nil) }
  scope :unused, -> { where(used_at: nil) }

  validates :user_id, presence: true
  validates :discord_username, presence: true
  validates :invite_code, presence: true, uniqueness: true

  # Create a new invite log entry
  # @param user [User] The user who generated the invite
  # @param invite_code [String] The Discord invite code
  # @param discord_username [String] The user's Discord username
  # @param github_username [String] The user's GitHub username (optional)
  # @param expires_at [Time] When the invite expires
  # @return [DiscordInviteLog]
  def self.log_invite(user:, invite_code:, discord_username:, github_username: nil, expires_at:)
    create!(
      user_id: user.id,
      invite_code: invite_code,
      discord_username: discord_username,
      github_username: github_username,
      created_at: Time.current,
      expires_at: expires_at,
      expired: false,
    )
  end

  # Mark invite as used
  # @return [Boolean]
  def mark_as_used!
    update!(used_at: Time.current)
  end

  # Mark invite as expired
  # @return [Boolean]
  def mark_as_expired!
    update!(expired: true)
  end

  # Check if invite is expired based on expires_at time
  # @return [Boolean]
  def expired?
    return true if expired
    Time.current > expires_at
  end

  # Get invite status as string
  # @return [String] "used", "expired", or "active"
  def status
    return "used" if used_at.present?
    return "expired" if expired?
    "active"
  end

  # Clean up old invite logs (older than 30 days)
  # @param retention_days [Integer] Number of days to keep logs
  # @return [Integer] Number of records deleted
  def self.cleanup_old_entries(retention_days = 30)
    cutoff_date = retention_days.days.ago
    records_to_delete = where("created_at < ?", cutoff_date)
    deleted_count = records_to_delete.count
    records_to_delete.destroy_all

    if deleted_count > 0
      Rails.logger.info(
        "Discord Invites: Cleaned up #{deleted_count} invite logs older than #{retention_days} days",
      )
    end

    deleted_count
  end

  # Mark expired invites based on expires_at timestamp
  # @return [Integer] Number of invites marked as expired
  def self.mark_expired_invites
    expired_invites = unexpired.where("expires_at < ?", Time.current)
    count = expired_invites.count
    expired_invites.update_all(expired: true)

    Rails.logger.info("Discord Invites: Marked #{count} invites as expired") if count > 0

    count
  end
end
