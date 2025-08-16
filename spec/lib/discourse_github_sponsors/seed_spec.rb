# frozen_string_literal: true

require_relative "../../plugin_helper"

RSpec.describe DiscourseGithubSponsors::Seed do
  before do
    SiteSetting.github_sponsors_group_name = "test-sponsors"
  end

  describe ".create_badge!" do
    context "when badge doesn't exist" do
      it "creates a new badge with correct attributes" do
        badge = DiscourseGithubSponsors::Seed.create_badge!

        expect(badge).to be_persisted
        expect(badge.name).to eq("GitHub Sponsor")
        expect(badge.description).to eq("Active GitHub Sponsor - Thank you for your support!")
        expect(badge.badge_type_id).to eq(BadgeType::Bronze)
        expect(badge.auto_revoke).to be true
        expect(badge.enabled).to be true
        expect(badge.listable).to be true
        expect(badge.show_posts).to be true
        expect(badge.allow_title).to be true
        expect(badge.icon).to eq("fab-github")
        expect(badge.badge_grouping_id).to eq(BadgeGrouping::Community)
      end

      it "sets the correct SQL query with the configured group name" do
        badge = DiscourseGithubSponsors::Seed.create_badge!

        expected_query = <<~SQL
          SELECT user_id, created_at granted_at, NULL post_id
          FROM group_users
          WHERE group_id = (
            SELECT id FROM groups WHERE name = 'test-sponsors'
          )
        SQL

        expect(badge.query.strip).to eq(expected_query.strip)
      end

      it "uses default group name when setting is nil" do
        SiteSetting.github_sponsors_group_name = nil
        badge = DiscourseGithubSponsors::Seed.create_badge!

        expect(badge.query).to include("WHERE name = 'sponsors'")
      end
    end

    context "when badge already exists" do
      let!(:existing_badge) do
        Badge.create!(
          name: "GitHub Sponsor",
          description: "Old description",
          badge_type_id: BadgeType::Gold,
          auto_revoke: false,
          enabled: false,
          query: "SELECT 1"
        )
      end

      it "updates the existing badge" do
        badge = DiscourseGithubSponsors::Seed.create_badge!

        expect(badge.id).to eq(existing_badge.id)
        expect(badge.description).to eq("Active GitHub Sponsor - Thank you for your support!")
        expect(badge.badge_type_id).to eq(BadgeType::Bronze)
        expect(badge.auto_revoke).to be true
        expect(badge.enabled).to be true
      end

      it "updates the query with current group name" do
        SiteSetting.github_sponsors_group_name = "new-sponsors"
        badge = DiscourseGithubSponsors::Seed.create_badge!

        expect(badge.query).to include("WHERE name = 'new-sponsors'")
      end
    end

    it "logs the badge creation" do
      Rails.logger.expects(:info).with(regexp_matches(/GitHub Sponsor badge created\/updated with ID: \d+/))
      DiscourseGithubSponsors::Seed.create_badge!
    end
  end

  describe ".grant_badges!" do
    let!(:badge) { DiscourseGithubSponsors::Seed.create_badge! }
    let!(:group) { Fabricate(:group, name: "test-sponsors") }
    let!(:user) { Fabricate(:user) }

    context "when badge exists" do
      it "calls BadgeGranter.backfill with the badge" do
        BadgeGranter.expects(:backfill).with(badge)
        DiscourseGithubSponsors::Seed.grant_badges!
      end

      it "logs the badge granting" do
        BadgeGranter.stubs(:backfill)
        Rails.logger.expects(:info).with("GitHub Sponsor badges granted via backfill")
        DiscourseGithubSponsors::Seed.grant_badges!
      end

      it "grants badges to users in the sponsors group" do
        group.add(user)
        
        expect {
          DiscourseGithubSponsors::Seed.grant_badges!
        }.to change { UserBadge.count }.by(1)

        user_badge = UserBadge.last
        expect(user_badge.user_id).to eq(user.id)
        expect(user_badge.badge_id).to eq(badge.id)
      end

      it "doesn't grant badges to users not in the sponsors group" do
        other_user = Fabricate(:user)
        group.add(user)  # Only add one user to the group
        
        DiscourseGithubSponsors::Seed.grant_badges!

        expect(UserBadge.where(user_id: other_user.id, badge_id: badge.id)).to be_empty
      end
    end

    context "when badge doesn't exist" do
      before do
        Badge.where(name: "GitHub Sponsor").destroy_all
      end

      it "returns early without error" do
        expect { DiscourseGithubSponsors::Seed.grant_badges! }.not_to raise_error
      end

      it "doesn't call BadgeGranter.backfill" do
        BadgeGranter.expects(:backfill).never
        DiscourseGithubSponsors::Seed.grant_badges!
      end
    end
  end
end
