# frozen_string_literal: true

require_relative "../plugin_helper"
require "webmock/rspec"

RSpec.describe Jobs::GithubSponsorsSync, type: :job do
  let(:job) { described_class.new }

  before { WebMock.disable_net_connect!(allow_localhost: true) }

  after { WebMock.reset! }

  describe "#execute" do
    context "when plugin is disabled" do
      before { SiteSetting.github_sponsors_enabled = false }

      it "doesn't perform sync" do
        job.execute({})
        expect(GithubSponsorSyncHistory.count).to eq(0)
      end
    end

    context "when plugin is enabled" do
      before { enable_github_sponsors_plugin }

      context "when GitHub account is not configured" do
        before { SiteSetting.github_sponsors_account = "" }

        it "logs error in sync history" do
          job.execute({})
          history = GithubSponsorSyncHistory.last
          expect(history.success).to eq(false)
          expect(history.error_message).to include("No GitHub account configured")
        end
      end

      context "with verbose logging enabled" do
        before do
          SiteSetting.github_sponsors_verbose_log = true
        end

        it "logs detailed sync information" do
          user1 = create_user_with_github("alice")
          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: ["alice"])

          # Setup logger as a spy
          allow(Rails.logger).to receive(:info)

          job.execute({})
          
          # Verify our verbose logging calls happened
          expect(Rails.logger).to have_received(:info).with("[GitHub Sponsors] Starting sync for test-org").once
          expect(Rails.logger).to have_received(:info).with("[GitHub Sponsors] Matched sponsor alice to user #{user1.username}").once
        end
      end

      context "when sponsors group doesn't exist" do
        before { Group.where(name: "sponsors").destroy_all }

        it "creates the sponsors group" do
          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: [])

          expect { job.execute({}) }.to change { Group.count }.by(1)

          group = Group.find_by(name: "sponsors")
          expect(group).to be_present
          expect(group.full_name).to eq("Sponsors")
          expect(group.visibility_level).to eq(Group.visibility_levels[:public])
        end

        it "sets flair settings from SiteSettings" do
          SiteSetting.github_sponsors_flair_icon = "seedling"
          SiteSetting.github_sponsors_flair_color = "525ddc"
          SiteSetting.github_sponsors_flair_bg_color = ""

          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: [])

          job.execute({})

          group = Group.find_by(name: "sponsors")
          expect(group.flair_icon).to eq("seedling")
          expect(group.flair_color).to eq("525ddc")
          expect(group.flair_bg_color).to be_nil
        end
      end

      context "when sponsors group exists" do
        let!(:group) { Fabricate(:group, name: "sponsors", flair_icon: "old-icon") }

        it "updates flair settings" do
          SiteSetting.github_sponsors_flair_icon = "new-icon"
          SiteSetting.github_sponsors_flair_color = "ffffff"

          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: [])

          job.execute({})

          group.reload
          expect(group.flair_icon).to eq("new-icon")
          expect(group.flair_color).to eq("ffffff")
        end
      end

      context "with GitHub sponsors" do
        let!(:group) { Fabricate(:group, name: "sponsors") }
        let!(:badge) { DiscourseGithubSponsors::Seed.create_badge! }
        let!(:user_with_github) { create_user_with_github("alice") }
        let!(:user_with_github_2) { create_user_with_github("bob") }
        let!(:user_without_github) { Fabricate(:user) }

        it "adds matched sponsors to the group" do
          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: %w[alice bob charlie])

          job.execute({})

          group.reload
          expect(group.users).to include(user_with_github, user_with_github_2)
          expect(group.users).not_to include(user_without_github)

          history = GithubSponsorSyncHistory.last
          expect(history.matched_sponsors).to eq(2)
          expect(history.unmatched_sponsors).to eq(1)  # Count, not array
        end

        it "sets user title when user has no title" do
          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: ["alice"])

          job.execute({})

          user_with_github.reload
          expect(user_with_github.title).to eq("GitHub Sponsor")
        end

        it "sets primary group for flair visibility" do
          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: ["alice"])

          job.execute({})

          user_with_github.reload
          expect(user_with_github.primary_group_id).to eq(group.id)

          history = GithubSponsorSyncHistory.last
          expect(history.added_users).to eq(1)  # This is a count
          expect(history.details["added_users"]).to eq(
            [{ "username" => user_with_github.username, "github" => "alice" }],
          )
        end

        it "calls BadgeGranter.backfill when adding users" do
          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: ["alice"])

          BadgeGranter.expects(:backfill).with(badge)
          job.execute({})
        end

        it "removes users who are no longer sponsors" do
          group.add(user_with_github)
          group.add(user_with_github_2)

          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: ["alice"]) # Only alice remains

          job.execute({})

          group.reload
          expect(group.users).to include(user_with_github)
          expect(group.users).not_to include(user_with_github_2)

          history = GithubSponsorSyncHistory.last
          expect(history.removed_users).to eq(1)  # This is a count
          expect(history.details["removed_users"]).to eq(
            [{ "username" => user_with_github_2.username, "github" => "bob" }],
          )
        end

        it "doesn't re-add users already in the group" do
          group.add(user_with_github)
          group.reload

          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: ["alice"])

          job.execute({})

          history = GithubSponsorSyncHistory.last
          # User was already in group, so added_users should be 0
          expect(history.added_users).to eq(0)
        end

        it "handles pagination correctly" do
          # Create 150 sponsors to test pagination
          sponsors_page_1 = (1..100).map { |i| "sponsor#{i}" }
          sponsors_page_2 = (101..150).map { |i| "sponsor#{i}" }

          stub_github_account_type_check("test-org", is_organization: true)

          # First request returns page 1 with hasNextPage: true
          stub_request(:post, "https://api.github.com/graphql")
            .with(body: hash_including("query" => /sponsorshipsAsMaintainer\(first: 100/))
            .to_return(
              status: 200,
              body: {
                "data" => {
                  "organization" => {
                    "sponsorshipsAsMaintainer" => {
                      "totalCount" => 150,
                      "pageInfo" => {
                        "hasNextPage" => true,
                        "endCursor" => "cursor123",
                      },
                      "nodes" =>
                        sponsors_page_1.map do |s|
                          { "sponsorEntity" => { "login" => s }, "isActive" => true }
                        end,
                    },
                  },
                },
              }.to_json,
            )
            .then
            .to_return(
              status: 200,
              body: {
                "data" => {
                  "organization" => {
                    "sponsorshipsAsMaintainer" => {
                      "totalCount" => 150,
                      "pageInfo" => {
                        "hasNextPage" => false,
                        "endCursor" => nil,
                      },
                      "nodes" =>
                        sponsors_page_2.map do |s|
                          { "sponsorEntity" => { "login" => s }, "isActive" => true }
                        end,
                    },
                  },
                },
              }.to_json,
            )

          job.execute({})

          history = GithubSponsorSyncHistory.last
          expect(history.total_sponsors).to eq(150)
          expect(history.details["sponsor_usernames"].length).to eq(150)
        end
      end

      context "with API errors" do
        let!(:group) { Fabricate(:group, name: "sponsors") }

        it "handles unauthorized error" do
          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_api_error(status: 401, message: "Bad credentials")

          job.execute({})

          history = GithubSponsorSyncHistory.last
          expect(history.success).to eq(false)
          expect(history.error_message).to eq("Failed to fetch sponsors from GitHub API")
        end

        it "handles GraphQL errors" do
          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_graphql_error(error_type: "INSUFFICIENT_SCOPES")

          job.execute({})

          history = GithubSponsorSyncHistory.last
          expect(history.success).to eq(false)
          expect(history.error_message).to eq("Failed to fetch sponsors from GitHub API")
        end

        it "returns error when API fails" do
          stub_github_account_type_check("test-org", is_organization: true)
          stub_request(:post, "https://api.github.com/graphql").with(
            body: /sponsorshipsAsMaintainer/,
          ).to_return(status: 500, body: "Internal Server Error")

          job.execute({})

          history = GithubSponsorSyncHistory.last
          expect(history.success).to eq(false)
          expect(history.error_message).to eq("Failed to fetch sponsors from GitHub API")
        end
      end

      context "with debug info" do
        let!(:group) { Fabricate(:group, name: "sponsors") }

        it "includes debug info in sync history" do
          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: [])

          job.execute({})

          history = GithubSponsorSyncHistory.last
          expect(history.total_sponsors).to eq(0)
          expect(history.details["sponsor_usernames"]).to eq([])
          expect(history.matched_sponsors).to eq(0)
          expect(history.unmatched_sponsors).to eq(0)
          expect(history.synced_at).to be_present
        end
      end

      context "with account type detection" do
        let!(:group) { Fabricate(:group, name: "sponsors") }

        it "correctly detects organization accounts" do
          stub_github_account_type_check("test-org", is_organization: true)
          stub_github_sponsors_request(sponsors: [], account: "test-org")

          job.execute({})

          history = GithubSponsorSyncHistory.last
          expect(history.success).to eq(true)
          expect(history.total_sponsors).to eq(0)
        end

        it "correctly detects user accounts" do
          SiteSetting.github_sponsors_account = "test-user"
          stub_github_account_type_check("test-user", is_organization: false)
          stub_github_user_sponsors_request(sponsors: [], account: "test-user")

          job.execute({})

          history = GithubSponsorSyncHistory.last
          expect(history.success).to eq(true)
          expect(history.total_sponsors).to eq(0)
        end

        it "defaults to user when detection fails" do
          # Stub account type check to fail
          stub_request(:post, "https://api.github.com/graphql").with(
            body: hash_including("query" => /organization/),
          ).to_return(status: 500, body: "Error")

          # Then expect user query
          stub_github_user_sponsors_request(sponsors: [], account: "test-org")

          job.execute({})

          history = GithubSponsorSyncHistory.last
          expect(history.success).to eq(true)
        end
      end
    end
  end
end
