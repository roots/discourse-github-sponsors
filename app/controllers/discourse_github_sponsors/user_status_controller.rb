# frozen_string_literal: true

module DiscourseGithubSponsors
  class UserStatusController < ::ApplicationController
    requires_plugin DiscourseGithubSponsors::PLUGIN_NAME

    before_action :ensure_logged_in

    def show
      sponsor_group = Group.find_by(name: SiteSetting.github_sponsors_group_name)

      if sponsor_group.nil?
        render json: { is_sponsor: false, group_id: nil, joined_at: nil }
        return
      end

      group_user = GroupUser.find_by(group_id: sponsor_group.id, user_id: current_user.id)

      if group_user
        render json: {
                 is_sponsor: true,
                 group_id: sponsor_group.id,
                 group_name: sponsor_group.name,
                 joined_at: group_user.created_at,
               }
      else
        render json: { is_sponsor: false, group_id: nil, joined_at: nil }
      end
    end
  end
end
