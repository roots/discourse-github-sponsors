# frozen_string_literal: true

class ProblemCheck::GithubTokenInvalid < ProblemCheck::InlineProblemCheck
  self.priority = "high"

  private

  def translation_key
    "dashboard.github_sponsors.github_token_invalid"
  end
end