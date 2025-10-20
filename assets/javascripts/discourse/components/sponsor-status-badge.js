import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

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
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
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
}
