# frozen_string_literal: true

module ::DiscourseGithubSponsors
  PLUGIN_NAME = "discourse-github-sponsors"

  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscourseGithubSponsors

    config.autoload_paths << File.join(config.root, "lib")

    scheduled_job_dir = "#{config.root}/app/jobs/scheduled"
    config.to_prepare do
      Rails.autoloaders.main.eager_load_dir(scheduled_job_dir) if Dir.exist?(scheduled_job_dir)
    end
  end

  def self.store
    @store ||= PluginStore.new(PLUGIN_NAME)
  end
end