# frozen_string_literal: true

require_relative "../plugin_helper"
require "webmock/rspec"

RSpec.describe "Full GitHub Sponsors Sync Flow", type: :request do
  let(:admin) { Fabricate(:admin) }
  let!(:badge) { DiscourseGithubSponsors::Seed.create_badge! }

  before do
    enable_github_sponsors_plugin
    WebMock.disable_net_connect!(allow_localhost: true)
    sign_in(admin)
  end

  after do
    WebMock.reset!
  end

  describe "complete sync workflow" do
    it "syncs sponsors, creates group, grants badges, and logs history" do
      # Create some users with GitHub accounts
      user1 = create_user_with_github("alice")
      user2 = create_user_with_github("bob")
      user3 = create_user_with_github("charlie")

      # Stub GitHub API responses
      stub_github_account_type_check("test-org", is_organization: true)
      stub_github_sponsors_request(sponsors: ["alice", "bob", "david"])

      # Initial state checks
      group = Group.find_by(name: "sponsors")
      expect(group).to be_nil
      expect(UserBadge.count).to eq(0)
      expect(GithubSponsorSyncHistory.count).to eq(0)

      # Perform sync
      post "/admin/plugins/github-sponsors/sync.json"
      expect(response.status).to eq(200)
      
      json = JSON.parse(response.body)
      expect(json["total_sponsors"]).to eq(3)
      expect(json["matched_sponsors"].length).to eq(2)
      expect(json["unmatched_sponsors"]).to eq(["david"])

      # Check group was created with correct settings
      group = Group.find_by(name: "sponsors")
      expect(group).to be_present
      expect(group.full_name).to eq("Sponsors")
      expect(group.visibility_level).to eq(Group.visibility_levels[:public])
      expect(group.flair_icon).to eq("fab-github")
      expect(group.flair_color).to eq("ffffff")

      # Check users were added to group
      expect(group.users).to include(user1, user2)
      expect(group.users).not_to include(user3)

      # Check primary groups were set for flair visibility
      user1.reload
      user2.reload
      expect(user1.primary_group_id).to eq(group.id)
      expect(user2.primary_group_id).to eq(group.id)

      # Check sync history was logged
      expect(GithubSponsorSyncHistory.count).to eq(1)
      history = GithubSponsorSyncHistory.last
      expect(history.success).to be true
      expect(history.total_sponsors).to eq(3)
      expect(history.matched_sponsors).to eq(2)
      expect(history.unmatched_sponsors).to eq(1)
      expect(history.added_users).to eq(2)
    end

    it "handles sponsor removal in subsequent sync" do
      # Create initial state with sponsors
      user1 = create_user_with_github("alice")
      user2 = create_user_with_github("bob")
      
      group = Group.create!(
        name: "sponsors",
        full_name: "Sponsors",
        visibility_level: Group.visibility_levels[:public]
      )
      group.add(user1)
      group.add(user2)

      # Alice is no longer a sponsor
      stub_github_account_type_check("test-org", is_organization: true)
      stub_github_sponsors_request(sponsors: ["bob"])

      # Perform sync
      post "/admin/plugins/github-sponsors/sync.json"
      expect(response.status).to eq(200)
      
      json = JSON.parse(response.body)
      expect(json["removed_users"].length).to eq(1)
      expect(json["removed_users"][0]["github"]).to eq("alice")

      # Check group membership
      group.reload
      expect(group.users).not_to include(user1)
      expect(group.users).to include(user2)

      # Check primary group was removed
      user1.reload
      expect(user1.primary_group_id).to be_nil
    end

    it "updates flair settings when site settings change" do
      # Create group with initial flair
      group = Group.create!(
        name: "sponsors",
        full_name: "Sponsors",
        visibility_level: Group.visibility_levels[:public],
        flair_icon: "old-icon",
        flair_color: "111111"
      )

      # Update site settings
      SiteSetting.github_sponsors_flair_icon = "seedling"
      SiteSetting.github_sponsors_flair_color = "525ddc"
      SiteSetting.github_sponsors_flair_bg_color = ""

      stub_github_account_type_check("test-org", is_organization: true)
      stub_github_sponsors_request(sponsors: [])

      # Perform sync
      post "/admin/plugins/github-sponsors/sync.json"
      expect(response.status).to eq(200)

      # Check flair was updated
      group.reload
      expect(group.flair_icon).to eq("seedling")
      expect(group.flair_color).to eq("525ddc")
      expect(group.flair_bg_color).to be_nil
    end

    it "handles API errors gracefully" do
      stub_github_account_type_check("test-org", is_organization: true)
      stub_github_api_error(status: 401, message: "Bad credentials")

      # Mock ProblemCheckTracker for 401 errors
      tracker = instance_double("ProblemCheckTracker")
      allow(ProblemCheckTracker).to receive(:[]).with(:github_token_invalid).and_return(tracker)
      allow(tracker).to receive(:problem!)

      # Perform sync
      post "/admin/plugins/github-sponsors/sync.json"
      expect(response.status).to eq(200)
      
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("Failed to fetch sponsors from GitHub API")

      # Check error was logged in history
      expect(GithubSponsorSyncHistory.count).to eq(1)
      history = GithubSponsorSyncHistory.last
      expect(history.success).to be false
      expect(history.error_message).to eq("Failed to fetch sponsors from GitHub API")
    end

    it "handles pagination for large sponsor lists" do
      # Create users for some of the sponsors
      users = (1..50).map { |i| create_user_with_github("sponsor#{i}") }

      # Stub pagination responses
      stub_github_account_type_check("test-org", is_organization: true)
      
      sponsors_page_1 = (1..100).map { |i| "sponsor#{i}" }
      sponsors_page_2 = (101..150).map { |i| "sponsor#{i}" }

      stub_request(:post, "https://api.github.com/graphql")
        .with(body: /sponsorshipsAsMaintainer\(first: 100/)
        .to_return(
          status: 200,
          body: {
            "data" => {
              "organization" => {
                "sponsorshipsAsMaintainer" => {
                  "totalCount" => 150,
                  "pageInfo" => {
                    "hasNextPage" => true,
                    "endCursor" => "cursor123"
                  },
                  "nodes" => sponsors_page_1.map { |s| 
                    { "sponsorEntity" => { "login" => s }, "isActive" => true }
                  }
                }
              }
            }
          }.to_json
        ).then
        .to_return(
          status: 200,
          body: {
            "data" => {
              "organization" => {
                "sponsorshipsAsMaintainer" => {
                  "totalCount" => 150,
                  "pageInfo" => {
                    "hasNextPage" => false,
                    "endCursor" => nil
                  },
                  "nodes" => sponsors_page_2.map { |s| 
                    { "sponsorEntity" => { "login" => s }, "isActive" => true }
                  }
                }
              }
            }
          }.to_json
        )

      # Perform sync
      post "/admin/plugins/github-sponsors/sync.json"
      expect(response.status).to eq(200)
      
      json = JSON.parse(response.body)
      expect(json["total_sponsors"]).to eq(150)
      expect(json["matched_sponsors"].length).to eq(50)
      expect(json["unmatched_sponsors"].length).to eq(100)

      # Check group membership
      group = Group.find_by(name: "sponsors")
      expect(group.users.count).to eq(50)
    end

    it "respects account type detection for users vs organizations" do
      user1 = create_user_with_github("alice")

      # Test with user account
      SiteSetting.github_sponsors_account = "test-user"
      stub_github_account_type_check("test-user", is_organization: false)
      stub_github_user_sponsors_request(sponsors: ["alice"], account: "test-user")

      post "/admin/plugins/github-sponsors/sync.json"
      expect(response.status).to eq(200)
      
      json = JSON.parse(response.body)
      expect(json["total_sponsors"]).to eq(1)
      expect(json["matched_sponsors"].length).to eq(1)
    end
  end

  describe "badge granting workflow" do
    it "grants badges via backfill after adding users to group" do
      user1 = create_user_with_github("alice")
      
      stub_github_account_type_check("test-org", is_organization: true)
      stub_github_sponsors_request(sponsors: ["alice"])

      # Mock BadgeGranter.backfill to verify it's called
      allow(BadgeGranter).to receive(:backfill).with(badge)

      post "/admin/plugins/github-sponsors/sync.json"
      expect(response.status).to eq(200)
      
      json = JSON.parse(response.body)
      expect(json["badges_granted"]).to be true
      
      expect(BadgeGranter).to have_received(:backfill).with(badge)
    end

    it "sets badge as user title when user has the badge" do
      user1 = create_user_with_github("alice")
      
      # Pre-grant the badge
      UserBadge.create!(
        user_id: user1.id,
        badge_id: badge.id,
        granted_at: Time.current,
        granted_by_id: -1
      )
      
      stub_github_account_type_check("test-org", is_organization: true)
      stub_github_sponsors_request(sponsors: ["alice"])

      post "/admin/plugins/github-sponsors/sync.json"
      expect(response.status).to eq(200)

      # User should have title set after sync
      user1.reload
      expect(user1.title).to eq("GitHub Sponsor")
    end
  end

  describe "sync history endpoint" do
    it "returns recent sync history" do
      # Create some history entries
      3.times do |i|
        GithubSponsorSyncHistory.create!(
          synced_at: (i + 1).hours.ago,
          total_sponsors: 10 - i,
          matched_sponsors: 5 - i,
          success: i != 1  # Second one failed
        )
      end

      get "/admin/plugins/github-sponsors/history.json"
      expect(response.status).to eq(200)
      
      json = JSON.parse(response.body)
      expect(json["history"].length).to eq(3)
      
      # Most recent first
      expect(json["history"][0]["total_sponsors"]).to eq(10)
      expect(json["history"][0]["success"]).to be true
      expect(json["history"][1]["success"]).to be false
    end
  end
end
