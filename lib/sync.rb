# frozen_string_literal: true

module DiscourseGithubSponsors
  class Sync
    def initialize
      @api = Api.new
    end

    def perform
      debug_info = {
        github_account: SiteSetting.github_sponsors_account,
        group_name: SiteSetting.github_sponsors_group_name,
        timestamp: Time.now.iso8601,
      }

      if SiteSetting.github_sponsors_verbose_log
        Rails.logger.info("[GitHub Sponsors] Starting sync for #{SiteSetting.github_sponsors_account}")
      end

      # Get or create the sponsors group
      sponsor_group = ensure_sponsors_group
      debug_info[:group_id] = sponsor_group.id
      debug_info[:group_created] = @group_created if @group_created

      github_account = SiteSetting.github_sponsors_account
      return { error: "No GitHub account configured" } if github_account.blank?

      sponsors = fetch_sponsors(github_account)
      return { error: "Failed to fetch sponsors from GitHub API" } if sponsors.nil?

      debug_info[:total_sponsors] = sponsors.length
      debug_info[:sponsor_usernames] = sponsors

      # Track matched and unmatched sponsors
      matched_sponsors = []
      unmatched_sponsors = []
      added_users = []
      removed_users = []
      already_in_group = []

      # Find users associated with GitHub accounts
      users_with_github =
        UserAssociatedAccount
          .where(provider_name: "github")
          .includes(:user)
          .select(:user_id, :provider_uid, :info)

      github_user_lookup = {}
      users_with_github.each do |account|
        # The info field is already a Hash, not a JSON string
        github_info = account.info || {}

        nickname = github_info["nickname"]&.downcase
        github_user_lookup[nickname] = account.user if nickname
      end

      debug_info[:discourse_users_with_github] = github_user_lookup.keys

      # Process sponsors
      sponsors.each do |sponsor_username|
        sponsor_username_lower = sponsor_username.downcase
        user = github_user_lookup[sponsor_username_lower]

        if SiteSetting.github_sponsors_verbose_log && user
          Rails.logger.info("[GitHub Sponsors] Matched sponsor #{sponsor_username} to user #{user.username}")
        end

        if user
          matched_sponsors << {
            github_username: sponsor_username,
            discourse_username: user.username,
            discourse_id: user.id,
          }
          if sponsor_group.users.exclude?(user)
            sponsor_group.add(user)
            user.update(title: "GitHub Sponsor") if user.title.blank?
            user.update(primary_group_id: sponsor_group.id) if user.primary_group_id.blank?
            added_users << { username: user.username, github: sponsor_username }
          else
            already_in_group << { username: user.username, github: sponsor_username }
          end
        else
          unmatched_sponsors << sponsor_username
        end
      end

      # Remove users who are no longer sponsors
      sponsor_group.users.each do |user|
        associated_account =
          UserAssociatedAccount.find_by(user_id: user.id, provider_name: "github")
        if associated_account
          # The info field is already a Hash, not a JSON string
          github_info = associated_account.info || {}
          nickname = github_info["nickname"]
          if sponsors.map(&:downcase).exclude?(nickname&.downcase)
            sponsor_group.remove(user)
            removed_users << { username: user.username, github: nickname }
          end
        end
      end

      debug_info[:matched_sponsors] = matched_sponsors
      debug_info[:unmatched_sponsors] = unmatched_sponsors
      debug_info[:added_users] = added_users
      debug_info[:removed_users] = removed_users
      debug_info[:already_in_group] = already_in_group
      debug_info[:current_group_size] = sponsor_group.users.count

      # Grant badges to any new group members
      if added_users.any?
        badge = Badge.find_by(name: "GitHub Sponsor")
        if badge
          BadgeGranter.backfill(badge)
          debug_info[:badges_granted] = true
        end
      end

      debug_info
    end

    private

    def ensure_sponsors_group
      group_name = SiteSetting.github_sponsors_group_name

      sponsor_group = Group.find_by(name: group_name)
      if sponsor_group
        # Update flair if settings changed
        sponsor_group.update(
          flair_icon: SiteSetting.github_sponsors_flair_icon,
          flair_color: SiteSetting.github_sponsors_flair_color,
          flair_bg_color: SiteSetting.github_sponsors_flair_bg_color.presence,
        )
      else
        @group_created = true
        sponsor_group =
          Group.create!(
            name: group_name,
            full_name: "Sponsors",
            visibility_level: Group.visibility_levels[:public],
            mentionable_level: Group::ALIAS_LEVELS[:nobody],
            messageable_level: Group::ALIAS_LEVELS[:nobody],
            flair_icon: SiteSetting.github_sponsors_flair_icon,
            flair_color: SiteSetting.github_sponsors_flair_color,
            flair_bg_color: SiteSetting.github_sponsors_flair_bg_color.presence,
          )
      end

      sponsor_group
    end

    def fetch_sponsors(account)
      all_sponsors = []
      has_next_page = true
      end_cursor = nil

      # Determine if account is a user or organization
      account_type = determine_account_type(account)

      while has_next_page
        cursor_param = end_cursor ? ", after: \"#{end_cursor}\"" : ""

        query = <<~GQL
          query {
            #{account_type}(login: "#{account}") {
              sponsorshipsAsMaintainer(first: 100#{cursor_param}, includePrivate: true) {
                totalCount
                pageInfo {
                  hasNextPage
                  endCursor
                }
                nodes {
                  sponsorEntity {
                    ... on User { login }
                    ... on Organization { login }
                  }
                  isActive
                }
              }
            }
          }
        GQL

        begin
          data = @api.query(query)
        rescue Api::RateLimitError => e
          Rails.logger.error("Rate limited while fetching sponsors: #{e.message}")
          raise e
        rescue Api::ApiError => e
          Rails.logger.error("API error while fetching sponsors: #{e.message}")
          return nil
        end

        # Extract sponsors from response
        sponsorships =
          data.dig("data", account_type.downcase, "sponsorshipsAsMaintainer", "nodes") || []
        sponsorships.each do |sponsorship|
          if sponsorship["isActive"]
            sponsor = sponsorship.dig("sponsorEntity", "login")
            all_sponsors << sponsor if sponsor
          end
        end

        # Check for next page
        page_info = data.dig("data", account_type.downcase, "sponsorshipsAsMaintainer", "pageInfo")
        if page_info
          has_next_page = page_info["hasNextPage"]
          end_cursor = page_info["endCursor"]
        else
          has_next_page = false
        end

        # Safety check to prevent infinite loops
        break if all_sponsors.length > 10_000
      end

      all_sponsors
    end

    def determine_account_type(account)
      query = <<~GQL
        query {
          organization(login: "#{account}") {
            id
          }
        }
      GQL

      begin
        # Cache account type for 24 hours since this rarely changes
        data = @api.query(query, cache_key: "account_type_#{account}", cache_ttl: 24.hours)
      rescue Api::ApiError => e
        Rails.logger.warn(
          "Could not determine account type for #{account}, assuming user: #{e.message}",
        )
        return "user"
      end

      # If organization exists, return "organization", otherwise "user"
      data.dig("data", "organization", "id") ? "organization" : "user"
    end
  end
end
