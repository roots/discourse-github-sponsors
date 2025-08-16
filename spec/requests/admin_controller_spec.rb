# frozen_string_literal: true

require_relative "../plugin_helper"
require "webmock/rspec"

RSpec.describe DiscourseGithubSponsors::AdminController, type: :request do
  let(:admin) { Fabricate(:admin) }
  let(:user) { Fabricate(:user) }
  let!(:group) { Fabricate(:group, name: "sponsors") }

  before do
    SiteSetting.github_sponsors_enabled = true  # Enable the plugin
    SiteSetting.github_sponsors_group_name = "sponsors"
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  after do
    WebMock.reset!
  end

  describe "#index" do
    context "when not logged in" do
      it "returns 404" do
        get "/admin/plugins/github-sponsors/sponsors.json"
        expect(response.status).to eq(404)
      end
    end

    context "when logged in as non-admin" do
      before { sign_in(user) }

      it "returns 404" do
        get "/admin/plugins/github-sponsors/sponsors.json"
        expect(response.status).to eq(404)
      end
    end

    context "when logged in as admin" do
      before do
        sign_in(admin)
        stub_github_rate_limit
      end

      it "returns sponsors data" do
        user_with_github = create_user_with_github("sponsor1")
        group.add(user_with_github)

        get "/admin/plugins/github-sponsors/sponsors.json"

        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json["sponsors"].length).to eq(1)
        expect(json["sponsors"][0]["username"]).to eq(user_with_github.username)
        expect(json["sponsors"][0]["github_username"]).to eq("sponsor1")
        expect(json["github_sponsors_enabled"]).to eq(true)
      end

      it "returns empty array when no sponsors" do
        get "/admin/plugins/github-sponsors/sponsors.json"

        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json["sponsors"]).to eq([])
      end
    end
  end

  describe "#history" do
    context "when not logged in" do
      it "returns 404" do
        get "/admin/plugins/github-sponsors/history.json"
        expect(response.status).to eq(404)
      end
    end

    context "when logged in as admin" do
      before { sign_in(admin) }

      it "returns sync history" do
        # Create some history entries
        GithubSponsorSyncHistory.create!(
          synced_at: 1.hour.ago,
          total_sponsors: 10,
          matched_sponsors: 5,
          unmatched_sponsors: 3,
          added_users: 2,
          removed_users: 1,
          success: true
        )

        GithubSponsorSyncHistory.create!(
          synced_at: 2.hours.ago,
          success: false,
          error_message: "API error"
        )

        get "/admin/plugins/github-sponsors/history.json"

        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json["history"].length).to eq(2)
        
        # Most recent first
        expect(json["history"][0]["success"]).to be true
        expect(json["history"][0]["total_sponsors"]).to eq(10)
        expect(json["history"][1]["success"]).to be false
        expect(json["history"][1]["error_message"]).to eq("API error")
      end

      it "returns empty array when no history" do
        get "/admin/plugins/github-sponsors/history.json"

        expect(response.status).to eq(200)
        json = JSON.parse(response.body)
        expect(json["history"]).to eq([])
      end
    end
  end

  describe "#sync" do
    context "when not logged in" do
      it "returns 404" do
        post "/admin/plugins/github-sponsors/sync.json"
        expect(response.status).to eq(404)
      end
    end

    context "when logged in as admin" do
      before { sign_in(admin) }

      context "when plugin is disabled" do
        before { SiteSetting.github_sponsors_enabled = false }

        it "returns 404 due to requires_plugin" do
          post "/admin/plugins/github-sponsors/sync.json"

          expect(response.status).to eq(404)
        end
      end

      context "when plugin is enabled" do
        before { enable_github_sponsors_plugin }

        context "when GitHub account is not configured" do
          before { SiteSetting.github_sponsors_account = "" }

          it "returns error" do
            post "/admin/plugins/github-sponsors/sync.json"

            expect(response.status).to eq(422)
            json = JSON.parse(response.body)
            expect(json["error"]).to include("GitHub account not configured")
          end
        end

        context "with valid configuration" do
          let!(:badge) { DiscourseGithubSponsors::Seed.create_badge! }
          let!(:user_with_github) { create_user_with_github("alice") }

          it "performs sync successfully" do
            stub_github_account_type_check("test-org", is_organization: true)
            stub_github_sponsors_request(sponsors: ["alice", "bob"])

            post "/admin/plugins/github-sponsors/sync.json"

            expect(response.status).to eq(200)
            json = JSON.parse(response.body)
            
            expect(json["total_sponsors"]).to eq(2)
            expect(json["matched_sponsors"].length).to eq(1)
            expect(json["unmatched_sponsors"]).to eq(["bob"])
            expect(json["added_users"].length).to eq(1)
            expect(json["current_group_size"]).to eq(1)
          end

          it "logs sync history on success" do
            stub_github_account_type_check("test-org", is_organization: true)
            stub_github_sponsors_request(sponsors: ["alice"])

            expect {
              post "/admin/plugins/github-sponsors/sync.json"
            }.to change { GithubSponsorSyncHistory.count }.by(1)

            history = GithubSponsorSyncHistory.last
            expect(history.success).to be true
            expect(history.total_sponsors).to eq(1)
          end

          it "updates group flair settings" do
            SiteSetting.github_sponsors_flair_icon = "star"
            SiteSetting.github_sponsors_flair_color = "ff0000"

            stub_github_account_type_check("test-org", is_organization: true)
            stub_github_sponsors_request(sponsors: [])

            post "/admin/plugins/github-sponsors/sync.json"

            group.reload
            expect(group.flair_icon).to eq("star")
            expect(group.flair_color).to eq("ff0000")
          end

          it "removes users no longer sponsoring" do
            group.add(user_with_github)

            stub_github_account_type_check("test-org", is_organization: true)
            stub_github_sponsors_request(sponsors: [])  # No sponsors

            post "/admin/plugins/github-sponsors/sync.json"

            expect(response.status).to eq(200)
            json = JSON.parse(response.body)
            expect(json["removed_users"].length).to eq(1)

            group.reload
            expect(group.users).to be_empty
          end

          it "handles API errors gracefully" do
            stub_github_account_type_check("test-org", is_organization: true)
            stub_github_api_error(status: 401, message: "Bad credentials")

            post "/admin/plugins/github-sponsors/sync.json"

            expect(response.status).to eq(200)
            json = JSON.parse(response.body)
            expect(json["error"]).to eq("Failed to fetch sponsors from GitHub API")
          end

          it "logs sync history on failure" do
            stub_github_account_type_check("test-org", is_organization: true)
            stub_github_api_error(status: 500, message: "Server error")

            expect {
              post "/admin/plugins/github-sponsors/sync.json"
            }.to change { GithubSponsorSyncHistory.count }.by(1)

            history = GithubSponsorSyncHistory.last
            expect(history.success).to be false
            expect(history.error_message).to eq("Failed to fetch sponsors from GitHub API")
          end

          it "handles pagination correctly" do
            # Create sponsors for pagination test
            sponsors_page_1 = (1..100).map { |i| "sponsor#{i}" }
            sponsors_page_2 = (101..150).map { |i| "sponsor#{i}" }

            stub_github_account_type_check("test-org", is_organization: true)

            # Stub first page
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

            post "/admin/plugins/github-sponsors/sync.json"

            expect(response.status).to eq(200)
            json = JSON.parse(response.body)
            expect(json["total_sponsors"]).to eq(150)
            expect(json["sponsor_usernames"].length).to eq(150)
          end
        end
      end
    end
  end
end
