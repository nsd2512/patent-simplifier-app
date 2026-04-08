require "json"

require_relative "patent_quality"
require_relative "patent_drafting"
require_relative "patent_search"

module PatentAssistant
  # Returns a structured assessment and a "missing info" checklist.
  def self.assess_idea(data)
    PatentQuality.assess_idea(data)
  end

  # Generates:
  # - an HTML draft the user can export/print
  # - a Mermaid diagram source (flowchart) for block diagrams
  # - a claims array (for utility apps)
  #
  # NOTE: This is a heuristic draft generator, not legal advice.
  def self.generate_draft(data)
    PatentDrafting.generate_draft(data)
  end

  # Prior-art search:
  # - derives query terms from the idea/draft payload
  # - calls the configured search provider (Google Custom Search JSON API by default)
  def self.search_prior_art(search_input)
    PatentSearch.search_prior_art(search_input)
  end
end

