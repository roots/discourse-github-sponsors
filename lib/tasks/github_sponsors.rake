# frozen_string_literal: true

namespace :github_sponsors do
  desc "Create or update the GitHub Sponsor badge"
  task create_badge: :environment do
    require_relative "../discourse_github_sponsors/seed"
    
    puts "Creating/updating GitHub Sponsor badge..."
    badge = DiscourseGithubSponsors::Seed.create_badge!
    puts "Badge created with ID: #{badge.id}"
    puts "Badge name: #{badge.name}"
    puts "Badge enabled: #{badge.enabled}"
    
    # Grant badges to existing group members
    DiscourseGithubSponsors::Seed.grant_badges!
    puts "Badges granted to existing group members"
  end
  
  desc "Grant badges to all current sponsors"
  task grant_badges: :environment do
    require_relative "../discourse_github_sponsors/seed"
    
    DiscourseGithubSponsors::Seed.grant_badges!
    puts "Badges granted to all current sponsors"
  end
  
  desc "Show badge status"
  task badge_status: :environment do
    badge = Badge.find_by(name: "GitHub Sponsor")
    if badge
      puts "GitHub Sponsor badge exists:"
      puts "  ID: #{badge.id}"
      puts "  Enabled: #{badge.enabled}"
      puts "  Auto-revoke: #{badge.auto_revoke}"
      puts "  Icon: #{badge.icon}"
      
      granted = UserBadge.where(badge_id: badge.id).count
      puts "  Granted to: #{granted} users"
    else
      puts "GitHub Sponsor badge not found"
    end
  end
end