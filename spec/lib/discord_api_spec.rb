# frozen_string_literal: true

require_relative "../plugin_helper"
require "webmock/rspec"

RSpec.describe DiscourseGithubSponsors::DiscordApi do
  let(:api) { described_class.new }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
    SiteSetting.discord_bot_token = "MTk4NjIyNDgzNDcxOTI1MjQ4.Cl2FMQ.ZnCjm1XVW7vRze4b7Cq4se7lk"
    SiteSetting.discord_server_guild_id = "461985401494700032"
    SiteSetting.discord_invite_channel_id = "819439093821603840"
    SiteSetting.discord_webhook_url =
      "https://discord.com/api/webhooks/1014168377469710347/test-webhook-token"
  end

  after { WebMock.reset! }

  describe "#member_exists?" do
    it "returns true when member is found" do
      stub_request(
        :get,
        "https://discord.com/api/v10/guilds/461985401494700032/members/search?query=testuser&limit=1",
      ).to_return(
        status: 200,
        body: [{ user: { username: "testuser", id: "123" } }].to_json,
        headers: {
          "Content-Type" => "application/json",
        },
      )

      expect(api.member_exists?("testuser")).to eq(true)
    end

    it "returns false when member is not found" do
      stub_request(
        :get,
        "https://discord.com/api/v10/guilds/461985401494700032/members/search?query=nonexistent&limit=1",
      ).to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

      expect(api.member_exists?("nonexistent")).to eq(false)
    end

    it "returns false when guild ID is blank" do
      SiteSetting.discord_server_guild_id = ""
      expect(api.member_exists?("testuser")).to eq(false)
    end

    it "handles API errors gracefully" do
      stub_request(
        :get,
        "https://discord.com/api/v10/guilds/461985401494700032/members/search?query=testuser&limit=1",
      ).to_return(status: 500, body: "Internal Server Error")

      expect(api.member_exists?("testuser")).to eq(false)
    end
  end

  describe "#create_invite" do
    it "creates an invite and returns the code" do
      stub_request(:post, "https://discord.com/api/v10/channels/819439093821603840/invites").with(
        body: { max_age: 3600, max_uses: 1 }.to_json,
      ).to_return(
        status: 200,
        body: { code: "abc123", expires_at: nil }.to_json,
        headers: {
          "Content-Type" => "application/json",
        },
      )

      expect(api.create_invite).to eq("abc123")
    end

    it "raises error when channel ID is blank" do
      SiteSetting.discord_invite_channel_id = ""

      expect { api.create_invite }.to raise_error(
        DiscourseGithubSponsors::DiscordApi::ApiError,
        "No Discord channel ID configured",
      )
    end

    it "raises PermissionError on 403 response" do
      stub_request(
        :post,
        "https://discord.com/api/v10/channels/819439093821603840/invites",
      ).to_return(
        status: 403,
        body: { message: "Missing Permissions", code: 50_013 }.to_json,
        headers: {
          "Content-Type" => "application/json",
        },
      )

      expect { api.create_invite }.to raise_error(
        DiscourseGithubSponsors::DiscordApi::PermissionError,
      )
    end

    it "raises ApiError on 401 response" do
      stub_request(
        :post,
        "https://discord.com/api/v10/channels/819439093821603840/invites",
      ).to_return(
        status: 401,
        body: { message: "Unauthorized", code: 0 }.to_json,
        headers: {
          "Content-Type" => "application/json",
        },
      )

      expect { api.create_invite }.to raise_error(
        DiscourseGithubSponsors::DiscordApi::ApiError,
        /Invalid Discord bot token/,
      )
    end
  end

  describe "#send_webhook_notification" do
    it "sends a notification successfully" do
      stub_request(
        :post,
        "https://discord.com/api/webhooks/1014168377469710347/test-webhook-token",
      ).with(body: { content: "Test message" }.to_json).to_return(status: 204)

      expect(api.send_webhook_notification("Test message")).to eq(true)
    end

    it "returns false when webhook URL is blank" do
      SiteSetting.discord_webhook_url = ""
      expect(api.send_webhook_notification("Test message")).to eq(false)
    end

    it "returns false on webhook error" do
      stub_request(
        :post,
        "https://discord.com/api/webhooks/1014168377469710347/test-webhook-token",
      ).to_return(status: 500)

      expect(api.send_webhook_notification("Test message")).to eq(false)
    end
  end

  describe "#rate_limit_status" do
    it "returns rate limit information" do
      status = api.rate_limit_status
      expect(status).to have_key(:remaining)
      expect(status).to have_key(:reset_at)
      expect(status).to have_key(:reset_in)
    end
  end

  describe "rate limiting" do
    it "waits when rate limited with short wait time" do
      # First request succeeds but sets rate limit to 0
      stub_request(
        :get,
        "https://discord.com/api/v10/guilds/461985401494700032/members/search?query=user1&limit=1",
      ).to_return(
        status: 200,
        body: "[]",
        headers: {
          "x-ratelimit-remaining" => "0",
          "x-ratelimit-reset" => (Time.now.to_f + 2).to_s,
        },
      )

      # Second request after waiting
      stub_request(
        :get,
        "https://discord.com/api/v10/guilds/461985401494700032/members/search?query=user2&limit=1",
      ).to_return(status: 200, body: "[]")

      api.member_exists?("user1")

      expect { api.member_exists?("user2") }.not_to raise_error
    end
  end
end
