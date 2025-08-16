# Discourse GitHub Sponsors Plugin

A Discourse plugin that integrates GitHub Sponsors with your Discourse forum, automatically syncing sponsor status and awarding badges to active sponsors.

## Features

- **GitHub API Integration** - Connects to GitHub GraphQL API with pagination support to fetch all active sponsors
- **Automatic Group Management** - Creates and manages a sponsors group with automatic membership updates
- **Scheduled Synchronization** - Background job runs every 6 hours to keep sponsor status up-to-date
- **Badge System** - Auto-grants/revokes badges based on sponsorship status
- **Customizable Flair** - Configure icon and colors for sponsor recognition
- **Admin Interface** - Full control panel with manual sync and history tracking
- **Sync History** - Track last 10 syncs with success/failure status and statistics
- **User Account Linking** - Matches GitHub sponsors to Discourse users via OAuth

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

### Required Settings

1. **GitHub API Token**
   - Create a personal access token at https://github.com/settings/tokens
   - Required scopes: `read:org`, `read:user`, `user:email`
   - Add token to `github_sponsors_token` setting

2. **GitHub Account**
   - Set `github_sponsors_account` to your GitHub username or organization

3. **Enable Plugin**
   - Set `github_sponsors_enabled` to true

### Optional Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `github_sponsors_group_name` | `sponsors` | Name of the group for sponsors |
| `github_sponsors_flair_icon` | `fab-github` | Font Awesome icon for sponsor flair |
| `github_sponsors_flair_color` | `ffffff` | Text color for flair (hex) |
| `github_sponsors_flair_bg_color` | _(empty)_ | Background color for flair (hex) |
| `github_sponsors_verbose_log` | `false` | Enable verbose logging for sync operations |
| `github_sponsors_sync_history_retention_days` | `30` | Days to retain sync history records |

## How It Works

1. Users must link their GitHub account in their Discourse preferences
2. The plugin runs a sync job every six hours to check sponsor status
3. Active sponsors are added to the configured group
4. Badges are automatically awarded based on group membership
5. User title and flair are set to show sponsor status

## Testing

### Manual Sync
Navigate to `/admin/plugins/github-sponsors` and click "Sync Sponsors Now"

### Command Line Sync
```bash
cd /var/discourse
./launcher enter app
rails c
Jobs::GithubSponsorsSync.new.execute({})
```

### Rake Tasks
```bash
# Create/update badge
LOAD_PLUGINS=1 bin/rake github_sponsors:create_badge

# Check badge status
LOAD_PLUGINS=1 bin/rake github_sponsors:badge_status
```

## Roadmap

- **Webhook Support** - Real-time updates when sponsorship status changes
- **Sponsorship Tiers** - Different badges per sponsorship tier
- **Grace Period** - Configurable grace period for declined sponsorships, send reminder notifications before removal
