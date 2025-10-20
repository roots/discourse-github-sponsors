import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

/**
 * @component sponsor-status-badge
 * Displays the current user's GitHub sponsor status
 * Shows a badge indicating whether they are an active sponsor
 */
export default class SponsorStatusBadge extends Component {
  @service siteSettings;

  /** @type {boolean} Loading state while fetching status */
  @tracked loading = true;

  /** @type {boolean} Whether the user is an active sponsor */
  @tracked isSponsor = false;

  /** @type {string|null} The name of the sponsors group */
  @tracked groupName = null;

  /** @type {boolean} Loading Discord status */
  @tracked discordLoading = false;

  /** @type {boolean} Whether Discord OAuth is linked */
  @tracked hasDiscordLinked = false;

  /** @type {boolean} Whether user is on Discord server */
  @tracked onDiscordServer = false;

  /** @type {string|null} User's Discord username */
  @tracked discordUsername = null;

  /** @type {boolean} Whether Discord check is configured */
  @tracked discordConfigured = true;

  /** @type {boolean} Loading state for invite generation */
  @tracked generatingInvite = false;

  /** @type {string|null} Generated invite URL */
  @tracked inviteUrl = null;

  /** @type {number|null} When the invite expires (timestamp) */
  @tracked inviteExpiresAt = null;

  constructor() {
    super(...arguments);
    this.loadSponsorStatus();
  }

  /**
   * Fetch the sponsor status from the API
   * @returns {Promise<void>}
   */
  async loadSponsorStatus() {
    try {
      const response = await ajax("/sponsors/status");
      this.isSponsor = response.is_sponsor;
      this.groupName = response.group_name;

      // If user is a sponsor, check Discord status
      if (this.isSponsor) {
        await this.loadDiscordStatus();
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * Fetch Discord status for the current user
   * @returns {Promise<void>}
   */
  async loadDiscordStatus() {
    this.discordLoading = true;
    try {
      const response = await ajax("/sponsors/discord/status");
      this.hasDiscordLinked = response.has_discord_linked;
      this.onDiscordServer = response.on_server;
      this.discordUsername = response.discord_username;
    } catch (error) {
      if (error.jqXHR?.status === 422) {
        // Discord not configured
        this.discordConfigured = false;
      } else {
        popupAjaxError(error);
      }
    } finally {
      this.discordLoading = false;
    }
  }

  /**
   * Generate a Discord invite link
   * @action
   * @returns {Promise<void>}
   */
  @action
  async generateInvite() {
    this.generatingInvite = true;
    try {
      const response = await ajax("/sponsors/discord/invite", {
        type: "POST",
      });

      this.inviteUrl = response.invite_url;
      this.inviteExpiresAt = response.expires_at;

      // Refresh Discord status to show they're now on the server (eventually)
      setTimeout(() => this.loadDiscordStatus(), 2000);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.generatingInvite = false;
    }
  }

  /**
   * Copy invite URL to clipboard
   * @action
   * @returns {Promise<void>}
   */
  @action
  async copyInvite() {
    if (this.inviteUrl) {
      try {
        await navigator.clipboard.writeText(this.inviteUrl);
        // Could add a toast notification here
      } catch {
        // Fallback for older browsers
        const textArea = document.createElement("textarea");
        textArea.value = this.inviteUrl;
        document.body.appendChild(textArea);
        textArea.select();
        document.execCommand("copy");
        document.body.removeChild(textArea);
      }
    }
  }

  /**
   * Get the sponsor URL from translations
   * @returns {string}
   */
  get sponsorUrl() {
    return this.siteSettings.github_sponsors_account
      ? `https://github.com/sponsors/${this.siteSettings.github_sponsors_account}`
      : "https://github.com/sponsors";
  }

  /**
   * Get time remaining until invite expires
   * @returns {string|null}
   */
  get expiresIn() {
    if (!this.inviteExpiresAt) {
      return null;
    }

    const now = Math.floor(Date.now() / 1000);
    const remaining = this.inviteExpiresAt - now;

    if (remaining <= 0) {
      return "Expired";
    }

    const minutes = Math.floor(remaining / 60);
    const seconds = remaining % 60;

    if (minutes > 0) {
      return `${minutes}m ${seconds}s`;
    }
    return `${seconds}s`;
  }

  <template>
    <div class="sponsor-status-badge">
      <h3>{{i18n "js.github_sponsors.sponsor_status.title"}}</h3>

      {{#if this.loading}}
        <p>
          {{i18n "js.github_sponsors.sponsor_status.checking"}}
        </p>
      {{else}}
        {{#if this.isSponsor}}
          <p>
            {{icon "heart"}}
            {{i18n "js.github_sponsors.sponsor_status.active"}}
          </p>

          {{#if this.discordConfigured}}
            <h3>{{i18n "js.github_sponsors.discord_access.title"}}</h3>

            {{#if this.discordLoading}}
              <p>
                {{i18n "js.github_sponsors.discord_access.checking"}}
              </p>
            {{else}}
              {{#if this.onDiscordServer}}
                <p>
                  {{icon "check"}}
                  {{i18n "js.github_sponsors.discord_access.on_server"}}
                </p>
              {{else if this.hasDiscordLinked}}
                {{#if this.inviteUrl}}
                  <p>
                    {{icon "check"}}
                    {{i18n "js.github_sponsors.discord_invite.success_title"}}
                  </p>
                  <p>
                    <a
                      href={{this.inviteUrl}}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="btn btn-primary"
                    >
                      {{i18n "js.github_sponsors.discord_invite.join_server"}}
                    </a>
                    <button
                      type="button"
                      class="btn btn-default"
                      {{on "click" this.copyInvite}}
                    >
                      {{i18n "js.github_sponsors.discord_invite.copy_link"}}
                    </button>
                  </p>
                  {{#if this.expiresIn}}
                    <p>
                      <em>{{i18n
                          "js.github_sponsors.discord_invite.expires_in"
                          time=this.expiresIn
                        }}</em>
                    </p>
                  {{/if}}
                {{else}}
                  <p>
                    {{i18n "js.github_sponsors.discord_access.can_join"}}
                  </p>
                  <p>
                    <button
                      type="button"
                      class="btn btn-primary"
                      {{on "click" this.generateInvite}}
                      disabled={{this.generatingInvite}}
                    >
                      {{#if this.generatingInvite}}
                        {{i18n "js.github_sponsors.discord_invite.generating"}}
                      {{else}}
                        {{i18n
                          "js.github_sponsors.discord_invite.generate_button"
                        }}
                      {{/if}}
                    </button>
                  </p>
                {{/if}}
              {{else}}
                <p>
                  {{i18n "js.github_sponsors.discord_access.not_linked"}}
                </p>
                <p>
                  <a href="/auth/discord" class="btn btn-primary">
                    {{i18n
                      "js.github_sponsors.discord_access.link_discord_button"
                    }}
                  </a>
                </p>
              {{/if}}
            {{/if}}
          {{/if}}
        {{else}}
          <p>
            {{i18n "js.github_sponsors.sponsor_status.inactive"}}
          </p>
          <p>
            <a
              href={{this.sponsorUrl}}
              target="_blank"
              rel="noopener noreferrer"
            >
              {{i18n "js.github_sponsors.sponsor_status.learn_more"}}
            </a>
          </p>
        {{/if}}
      {{/if}}
    </div>
  </template>
}
