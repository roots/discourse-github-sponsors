# frozen_string_literal: true

class CreateDiscordInviteLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :discourse_github_sponsors_discord_invite_logs do |t|
      t.integer :user_id, null: false
      t.string :github_username, limit: 255
      t.string :discord_username, limit: 255, null: false
      t.string :invite_code, limit: 50, null: false
      t.datetime :created_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.boolean :expired, default: false, null: false

      t.index :user_id, name: "idx_discord_invites_user_id"
      t.index :created_at, name: "idx_discord_invites_created_at"
      t.index :invite_code, unique: true, name: "idx_discord_invites_code"
    end
  end
end
