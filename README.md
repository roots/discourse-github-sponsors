# Discourse GitHub Sponsors Plugin

A Discourse plugin that integrates GitHub Sponsors with your Discourse forum, automatically syncing sponsor status and awarding badges to active sponsors.

## Features

### GitHub Sponsors Sync
- **GitHub API Integration** - Connects to GitHub GraphQL API with pagination support to fetch all active sponsors
- **Automatic Group Management** - Creates and manages a sponsors group with automatic membership updates
- **Scheduled Synchronization** - Background job runs every 6 hours to keep sponsor status up-to-date
- **Badge System** - Auto-grants/revokes badges based on sponsorship status
- **Customizable Flair** - Configure icon and colors for sponsor recognition
- **Admin Interface** - Full control panel with manual sync and history tracking
- **Sync History** - Track last 10 syncs with success/failure status and statistics
- **User Account Linking** - Matches GitHub sponsors to Discourse users via OAuth

### Discord Server Access (Optional)
- **Automated Discord Invites** - Generate single-use Discord server invites for active sponsors
- **Member Verification** - Check if sponsors are already on your Discord server
- **OAuth Integration** - Seamlessly integrates with Discord OAuth for account linking
- **Invite Tracking** - Admin dashboard showing invite history, usage statistics, and status
- **Webhook Notifications** - Get notified when sponsors generate Discord invites
- **Automatic Expiry** - Invites expire after 1 hour and are single-use only

## Installation

1. Add the plugin to your Discourse `containers/app.yml` file:
```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/roots/discourse-github-sponsors.git
```

2. Rebuild your Discourse container:
```bash
cd /var/discourse
./launcher rebuild app
```

## Configuration

### GitHub Sponsors Setup

#### Required Settings

1. **GitHub API Token**
   - Create a personal access token at https://github.com/settings/tokens
   - Required scopes: `read:org`, `read:user`, `user:email`
   - Add token to `github_sponsors_token` setting

2. **GitHub Account**
   - Set `github_sponsors_account` to your GitHub username or organization

3. **Enable Plugin**
   - Set `github_sponsors_enabled` to true

#### Optional Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `github_sponsors_group_name` | `sponsors` | Name of the group for sponsors |
| `github_sponsors_flair_icon` | `fab-github` | Font Awesome icon for sponsor flair |
| `github_sponsors_flair_color` | `ffffff` | Text color for flair (hex) |
| `github_sponsors_flair_bg_color` | _(empty)_ | Background color for flair (hex) |
| `github_sponsors_verbose_log` | `false` | Enable verbose logging for sync operations |
| `github_sponsors_sync_history_retention_days` | `30` | Days to retain sync history records |

### Discord Integration Setup (Optional)

The Discord integration allows active GitHub sponsors to generate single-use invite links to join your Discord server.

#### 1. Create Discord Bot

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click "New Application" and give it a name
3. Navigate to the "Bot" section and click "Add Bot"
4. Under "Privileged Gateway Intents", enable:
   - **Server Members Intent** (required for member search)
5. Copy the bot token (you'll need this for `discord_bot_token` setting)

#### 2. Add Bot to Your Server

1. Go to the "OAuth2" → "URL Generator" section
2. Select these scopes:
   - `bot`
3. Select these bot permissions:
   - **Create Instant Invite** (permission value: 1)
   - **View Channels** (permission value: 1024)
   - Total permission integer: **1025**
4. Copy the generated URL and open it in your browser
5. Select your Discord server and authorize the bot

#### 3. Get Server and Channel IDs

1. Enable Developer Mode in Discord:
   - User Settings → App Settings → Advanced → Developer Mode
2. Right-click your server name and select "Copy Server ID"
3. Right-click the channel where invites should be generated and select "Copy Channel ID"

#### 4. Configure Discord Settings

| Setting | Required | Description |
|---------|----------|-------------|
| `discord_server_guild_id` | Yes | Your Discord server (guild) ID |
| `discord_invite_channel_id` | Yes | Channel ID where bot will generate invites |
| `discord_bot_token` | Yes | Discord bot token (keep secret!) |
| `discord_webhook_url` | No | Optional webhook URL for invite notifications |
| `discord_invite_max_age` | No | Invite expiry time in seconds (default: 3600 = 1 hour) |

**Important**: The bot token is a secret and should never be shared publicly or committed to version control.

## How It Works

### GitHub Sponsors Sync

1. Users must link their GitHub account in their Discourse preferences
2. The plugin runs a sync job every six hours to check sponsor status
3. Active sponsors are added to the configured group
4. Badges are automatically awarded based on group membership
5. User title and flair are set to show sponsor status

### Discord Integration (Optional)

1. **User Requirements**:
   - Must be an active GitHub sponsor (in the sponsors group)
   - Must link their Discord account via Discourse OAuth

2. **Invite Generation Flow**:
   - Sponsors navigate to their account preferences page
   - The plugin checks if they're already on the Discord server
   - If not on server, they can generate a single-use invite link
   - Invite expires after 1 hour (configurable)
   - All invites are logged in the database for admin tracking

3. **Admin Dashboard**:
   - View complete invite history (last 50 invites)
   - See statistics: total invites, used, expired, active, usage rate
   - Monitor which users generated invites and when
   - Track invite status (used/expired/active)

## Testing

### GitHub Sponsors Sync

#### Manual Sync
Navigate to `/admin/plugins/github-sponsors` and click "Sync Sponsors Now"

#### Command Line Sync
```bash
cd /var/discourse
./launcher enter app
rails c
Jobs::GithubSponsorsSync.new.execute({})
```

#### Rake Tasks
```bash
# Create/update badge
LOAD_PLUGINS=1 bin/rake github_sponsors:create_badge

# Check badge status
LOAD_PLUGINS=1 bin/rake github_sponsors:badge_status
```

## License

MIT
