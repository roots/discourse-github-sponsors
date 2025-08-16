# frozen_string_literal: true

class CreateGithubSponsorSyncHistory < ActiveRecord::Migration[7.0]
  def change
    unless table_exists?(:github_sponsor_sync_histories)
      create_table :github_sponsor_sync_histories do |t|
        t.datetime :synced_at, null: false
        t.integer :total_sponsors, default: 0
        t.integer :matched_sponsors, default: 0
        t.integer :unmatched_sponsors, default: 0
        t.integer :added_users, default: 0
        t.integer :removed_users, default: 0
        t.boolean :success, default: true
        t.text :error_message
        t.json :details
        t.timestamps
      end

      add_index :github_sponsor_sync_histories, :synced_at unless index_exists?(:github_sponsor_sync_histories, :synced_at)
      add_index :github_sponsor_sync_histories, :success unless index_exists?(:github_sponsor_sync_histories, :success)
      add_index :github_sponsor_sync_histories, [:synced_at, :success] unless index_exists?(:github_sponsor_sync_histories, [:synced_at, :success])
    end
  end
end