import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";

/**
 * @component admin-plugins-github-sponsors
 * Controller for the GitHub Sponsors admin interface
 * Manages sponsor syncing, history display, and API rate limits
 */
export default class AdminPluginsGithubSponsors extends Controller {
  /** @type {boolean} Loading state for sync operation */
  @tracked loading = false;

  /** @type {Object|null} Debug information from last sync */
  @tracked debugInfo = null;

  /** @type {string|null} Timestamp of last sync */
  @tracked lastSyncTime = null;

  /** @type {Array} Recent sync history entries */
  @tracked syncHistory = [];

  /** @type {boolean} Loading state for history fetch */
  @tracked historyLoading = false;

  /** @type {Object|null} GitHub API rate limit status */
  @tracked rateLimit = null;

  /**
   * Initialize controller and load initial data
   * @returns {Promise<void>}
   */
  async init() {
    super.init(...arguments);
    this.loadHistory();
    this.loadRateLimit();
  }

  /**
   * Load sync history from the server
   * @action
   * @returns {Promise<void>}
   */
  @action
  async loadHistory() {
    this.historyLoading = true;
    try {
      const response = await ajax("/admin/plugins/github-sponsors/history");
      this.syncHistory = response.history;
    } catch {
      // Error loading sync history
    } finally {
      this.historyLoading = false;
    }
  }

  /**
   * Load GitHub API rate limit status
   * @action
   * @returns {Promise<void>}
   */
  @action
  async loadRateLimit() {
    try {
      const response = await ajax("/admin/plugins/github-sponsors/sponsors");
      this.rateLimit = response.rate_limit;
    } catch {
      // Error loading rate limit
    }
  }

  /**
   * Trigger a manual sync of GitHub sponsors
   * @action
   * @returns {Promise<void>}
   */
  @action
  async syncSponsors() {
    this.loading = true;

    try {
      const response = await ajax("/admin/plugins/github-sponsors/sync", {
        type: "POST",
      });

      this.debugInfo = response;
      this.lastSyncTime = new Date().toLocaleString();
      // Reload history and rate limit after successful sync
      this.loadHistory();
      this.loadRateLimit();
    } catch (error) {
      // Extract more error details
      let errorMessage = "Unknown error";
      let errorDetails = {};

      if (error.jqXHR) {
        // This is an AJAX error
        errorMessage = `HTTP ${error.jqXHR.status}: ${error.jqXHR.statusText}`;
        errorDetails = {
          status: error.jqXHR.status,
          statusText: error.jqXHR.statusText,
          responseText: error.jqXHR.responseText,
          responseJSON: error.jqXHR.responseJSON,
        };

        // Try to extract Rails error message
        if (error.jqXHR.responseJSON && error.jqXHR.responseJSON.errors) {
          errorMessage = error.jqXHR.responseJSON.errors.join(", ");
        } else if (error.jqXHR.responseJSON && error.jqXHR.responseJSON.error) {
          errorMessage = error.jqXHR.responseJSON.error;
        }
      } else if (error.message) {
        errorMessage = error.message;
      } else if (typeof error === "string") {
        errorMessage = error;
      }

      this.debugInfo = {
        error: errorMessage,
        details: JSON.stringify(errorDetails, null, 2),
        stack: error.stack,
        fullError: JSON.stringify(error, null, 2),
      };
    } finally {
      this.loading = false;
    }
  }
}
