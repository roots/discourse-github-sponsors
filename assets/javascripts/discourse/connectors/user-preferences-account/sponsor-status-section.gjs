import Component from "@glimmer/component";
import { service } from "@ember/service";
import SponsorStatusBadge from "../../components/sponsor-status-badge";

export default class SponsorStatusSection extends Component {
  @service siteSettings;

  <template>
    {{#if this.siteSettings.github_sponsors_enabled}}
      <div class="sponsor-status-section">
        <SponsorStatusBadge />
      </div>
    {{/if}}
  </template>
}
