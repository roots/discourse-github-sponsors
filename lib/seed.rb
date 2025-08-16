# frozen_string_literal: true

module DiscourseGithubSponsors
  class Seed
    def self.create_badge!
      group_name = SiteSetting.github_sponsors_group_name.presence || "sponsors"

      # Find or create the GitHub Sponsor badge
      badge = Badge.find_or_initialize_by(name: "GitHub Sponsor")

      badge.assign_attributes(
        description: "Active GitHub Sponsor - Thank you for your support!",
        badge_type_id: BadgeType::Bronze, # Can be Bronze(3), Silver(2), Gold(1)
        target_posts: false,
        enabled: true,
        auto_revoke: true,
        listable: true,
        show_posts: true, # Show badge on posts/topics
        system: false,
        multiple_grant: false,
        allow_title: true, # Allow users to use this badge as their title
        icon: "fab-github", # FontAwesome GitHub icon
        badge_grouping_id: BadgeGrouping::Community,
      )

      # Set the group-based query - properly escaped
      escaped_group_name = ActiveRecord::Base.connection.quote(group_name)
      badge.query = <<~SQL
        SELECT user_id, created_at granted_at, NULL post_id
        FROM group_users
        WHERE group_id = (
          SELECT id FROM groups WHERE name = #{escaped_group_name}
        )
      SQL

      badge.save!

      Rails.logger.info "GitHub Sponsor badge created/updated with ID: #{badge.id}"
      badge
    end

    def self.grant_badges!
      badge = Badge.find_by(name: "GitHub Sponsor")
      return unless badge

      BadgeGranter.backfill(badge)
      Rails.logger.info "GitHub Sponsor badges granted via backfill"
    end
  end
end
