# frozen_string_literal: true

require_relative "../../../spec/rails_helper"

module GithubSponsorsSpecHelper
  def create_user_with_github(github_username)
    user = Fabricate(:user)
    UserAssociatedAccount.create!(
      user_id: user.id,
      provider_name: "github",
      provider_uid: "12345_#{github_username}",
      info: { "nickname" => github_username },
    )
    user
  end

  def stub_github_sponsors_request(sponsors: [], account: "test-org", account_type: "organization")
    response = {
      "data" => {
        account_type.downcase => {
          "sponsorshipsAsMaintainer" => {
            "totalCount" => sponsors.length,
            "pageInfo" => {
              "hasNextPage" => false,
              "endCursor" => nil
            },
            "nodes" => sponsors.map { |s| { "sponsorEntity" => { "login" => s }, "isActive" => true } }
          }
        }
      }
    }

    stub_request(:post, "https://api.github.com/graphql")
      .with(body: hash_including("query" => /sponsorshipsAsMaintainer/))
      .to_return(status: 200, body: response.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_github_user_sponsors_request(sponsors: [], account: "test-user")
    stub_github_sponsors_request(sponsors: sponsors, account: account, account_type: "user")
  end

  def stub_github_account_type_check(account, is_organization: true)
    # First stub the rate limit check that happens automatically
    stub_github_rate_limit
    
    response = {
      "data" => {
        "organization" => is_organization ? { "id" => "MDEyOk9yZ2FuaXphdGlvbjE=" } : nil
      }
    }

    stub_request(:post, "https://api.github.com/graphql")
      .with(body: hash_including("query" => /organization\(login: "#{account}"\)/))
      .to_return(status: 200, body: response.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_github_api_error(status: 401, message: "Bad credentials")
    # Stub rate limit check to fail too
    error_response = {
      "message" => message,
      "documentation_url" => "https://docs.github.com/graphql"
    }

    # Stub all GraphQL requests to return the error
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(status: status, body: error_response.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_github_graphql_error(error_type: "INSUFFICIENT_SCOPES")
    error_response = {
      "errors" => [
        {
          "type" => error_type,
          "message" => "Your token has not been granted the required scopes"
        }
      ]
    }

    # Stub all GraphQL requests to return the error
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(status: 200, body: error_response.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_github_rate_limit(remaining: 5000, reset_at: 1.hour.from_now)
    rate_limit_response = {
      "data" => {
        "rateLimit" => {
          "remaining" => remaining,
          "resetAt" => reset_at.iso8601
        }
      }
    }
    
    stub_request(:post, "https://api.github.com/graphql")
      .with(body: /rateLimit/)
      .to_return(status: 200, body: rate_limit_response.to_json, headers: { "Content-Type" => "application/json" })
  end

  def enable_github_sponsors_plugin
    SiteSetting.github_sponsors_enabled = true
    SiteSetting.github_sponsors_account = "test-org"
    SiteSetting.github_sponsors_token = "ghp_" + "x" * 36  # Valid format: ghp_ + 36 chars
    SiteSetting.github_sponsors_group_name = "sponsors"
    
    # Always stub rate limit by default to prevent API calls
    stub_github_rate_limit
  end
end

RSpec.configure do |config|
  config.include GithubSponsorsSpecHelper
  
  config.before(:each) do |example|
    if example.metadata[:type] == :request || example.metadata[:type] == :model || example.metadata[:type] == :job
      SiteSetting.github_sponsors_enabled = false
    end
  end
end