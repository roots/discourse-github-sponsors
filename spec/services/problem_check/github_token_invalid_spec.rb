# frozen_string_literal: true

require_relative "../../plugin_helper"

RSpec.describe ProblemCheck::GithubTokenInvalid do
  subject(:check) { described_class.new }

  describe "#check" do
    it "returns the correct translation key" do
      # Problem checks use the translation_key method
      expect(check.send(:translation_key)).to eq("dashboard.github_sponsors.github_token_invalid")
    end
  end
end