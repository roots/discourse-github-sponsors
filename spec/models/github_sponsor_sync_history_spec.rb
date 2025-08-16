# frozen_string_literal: true

require_relative "../plugin_helper"

RSpec.describe GithubSponsorSyncHistory, type: :model do
  describe ".log_sync" do
    context "with successful sync" do
      it "creates a history entry with correct counts" do
        result = {
          total_sponsors: 10,
          matched_sponsors: [1, 2, 3],
          unmatched_sponsors: ["user1", "user2"],
          added_users: [{ username: "test" }],
          removed_users: [],
          sponsor_usernames: ["user1", "user2", "user3"]
        }

        entry = GithubSponsorSyncHistory.log_sync(result)

        expect(entry).to be_persisted
        expect(entry.total_sponsors).to eq(10)
        expect(entry.matched_sponsors).to eq(3)
        expect(entry.unmatched_sponsors).to eq(2)
        expect(entry.added_users).to eq(1)
        expect(entry.removed_users).to eq(0)
        expect(entry.success).to be true
        expect(entry.error_message).to be_nil
        expect(entry.details["sponsor_usernames"]).to eq(["user1", "user2", "user3"])
      end

      it "handles nil arrays gracefully" do
        result = {
          total_sponsors: 0,
          matched_sponsors: nil,
          unmatched_sponsors: nil,
          added_users: nil,
          removed_users: nil
        }

        entry = GithubSponsorSyncHistory.log_sync(result)

        expect(entry).to be_persisted
        expect(entry.matched_sponsors).to eq(0)
        expect(entry.unmatched_sponsors).to eq(0)
        expect(entry.added_users).to eq(0)
        expect(entry.removed_users).to eq(0)
        expect(entry.success).to be true
      end
    end

    context "with failed sync" do
      it "creates a history entry with error message" do
        result = {}
        error_message = "GitHub API rate limit exceeded"

        entry = GithubSponsorSyncHistory.log_sync(result, error_message)

        expect(entry).to be_persisted
        expect(entry.success).to be false
        expect(entry.error_message).to eq(error_message)
        expect(entry.total_sponsors).to eq(0)
      end
    end

    it "stores details in JSON column" do
      result = {
        sponsor_usernames: ["alice", "bob"],
        added_users: [{ username: "alice", github: "alice-gh" }],
        removed_users: [{ username: "charlie", github: "charlie-gh" }],
        other_data: "should not be stored"
      }

      entry = GithubSponsorSyncHistory.log_sync(result)

      expect(entry.details["sponsor_usernames"]).to eq(["alice", "bob"])
      expect(entry.details["added_users"]).to eq([{ "username" => "alice", "github" => "alice-gh" }])
      expect(entry.details["removed_users"]).to eq([{ "username" => "charlie", "github" => "charlie-gh" }])
      expect(entry.details["other_data"]).to be_nil
    end
  end

  describe ".recent" do
    it "returns last 10 entries ordered by synced_at desc" do
      # Create 15 entries with different times
      15.times do |i|
        GithubSponsorSyncHistory.create!(
          synced_at: i.hours.ago,
          total_sponsors: i
        )
      end

      recent = GithubSponsorSyncHistory.recent

      expect(recent.count).to eq(10)
      expect(recent.first.total_sponsors).to eq(0)  # Most recent
      expect(recent.last.total_sponsors).to eq(9)   # 10th most recent
    end
  end

  describe ".successful" do
    it "returns only successful syncs" do
      successful = GithubSponsorSyncHistory.create!(synced_at: Time.current, success: true)
      failed = GithubSponsorSyncHistory.create!(synced_at: Time.current, success: false)

      results = GithubSponsorSyncHistory.successful

      expect(results).to include(successful)
      expect(results).not_to include(failed)
    end
  end

  describe ".failed" do
    it "returns only failed syncs" do
      successful = GithubSponsorSyncHistory.create!(synced_at: Time.current, success: true)
      failed = GithubSponsorSyncHistory.create!(synced_at: Time.current, success: false)

      results = GithubSponsorSyncHistory.failed

      expect(results).not_to include(successful)
      expect(results).to include(failed)
    end
  end

  describe ".cleanup_old_entries" do
    it "removes entries older than 30 days" do
      recent = GithubSponsorSyncHistory.create!(synced_at: 1.day.ago)
      old = GithubSponsorSyncHistory.create!(synced_at: 31.days.ago)
      very_old = GithubSponsorSyncHistory.create!(synced_at: 60.days.ago)

      GithubSponsorSyncHistory.cleanup_old_entries

      expect(GithubSponsorSyncHistory.exists?(recent.id)).to be true
      expect(GithubSponsorSyncHistory.exists?(old.id)).to be false
      expect(GithubSponsorSyncHistory.exists?(very_old.id)).to be false
    end

    it "returns the count of deleted records" do
      3.times { GithubSponsorSyncHistory.create!(synced_at: 31.days.ago) }
      2.times { GithubSponsorSyncHistory.create!(synced_at: 1.day.ago) }

      result = GithubSponsorSyncHistory.cleanup_old_entries

      expect(result).to eq(3)
    end
  end
end
