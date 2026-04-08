require "net/http"
require "uri"
require "json"

module PatentSearch
  GOOGLE_BASE_URL = "https://www.googleapis.com/customsearch/v1".freeze

  def self.search_prior_art(search_input)
    input = (search_input || {}).transform_keys(&:to_s)

    query_core = input["queryCore"].to_s.strip
    query_terms = Array(input["queryTerms"]).map(&:to_s).map(&:strip).reject(&:empty?)
    external_sources = Array(input["externalSources"]).map(&:to_s).map(&:strip).reject(&:empty?)

    google_key = ENV["GOOGLE_API_KEY"].to_s.strip
    google_cse_id = ENV["GOOGLE_CSE_ID"].to_s.strip

    if google_key.empty? || google_cse_id.empty?
      return {
        "configured" => false,
        "status" => "not_configured",
        "message" => "Set GOOGLE_API_KEY and GOOGLE_CSE_ID (Google Custom Search) to enable automated prior-art search.",
        "query" => {
          "queryCore" => query_core,
          "queryTerms" => query_terms
        },
        "results" => [],
        "noveltyRisk" => nil
      }
    end

    # Build a small set of targeted queries to keep results consistent.
    base_terms = query_terms.take(4)
    base_terms = [query_core].concat(base_terms).reject(&:empty?).take(6)

    google_queries = []
    base_terms.each do |t|
      next if t.to_s.strip.empty?
      google_queries << t
      google_queries << "site:uspto.gov #{t}"
      google_queries << "site:patents.google.com #{t}"
    end

    # De-dup and cap.
    google_queries = google_queries.uniq.take(8)

    results = []
    seen_urls = {}

    google_queries.each do |q|
      provider_results = google_custom_search(google_key, google_cse_id, q, 5)
      provider_results.each do |r|
        url = r["link"].to_s
        next if url.empty?
        next if seen_urls[url]
        seen_urls[url] = true

        results << {
          "query" => q,
          "title" => r["title"].to_s,
          "link" => url,
          "snippet" => r["snippet"].to_s
        }
      end
    end

    novelty = compute_novelty_risk(query_core, query_terms, results)

    {
      "configured" => true,
      "status" => "ok",
      "query" => {
        "queryCore" => query_core,
        "queryTerms" => query_terms,
        "externalSources" => external_sources
      },
      "results" => results.take(25),
      "noveltyRisk" => novelty
    }
  end

  def self.google_custom_search(api_key, cx, query, num)
    uri = URI(GOOGLE_BASE_URL)
    uri.query = URI.encode_www_form(
      "key" => api_key,
      "cx" => cx,
      "q" => query,
      "num" => num.to_i
    )

    res = Net::HTTP.get_response(uri)
    return [] unless res.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(res.body.to_s)
    items = parsed["items"]
    return [] unless items.is_a?(Array)

    items
  rescue => e
    []
  end

  def self.compute_novelty_risk(query_core, query_terms, results)
    # Heuristic risk:
    # - Higher if many results match multiple query terms in title/snippet
    # - Lower if results are sparse/irrelevant
    terms = []
    terms << query_core unless query_core.empty?
    terms.concat(query_terms)
    terms = terms.flat_map { |t| t.to_s.split(/\s+/) }.map(&:downcase)
    terms = terms.reject { |t| t.length < 4 }.uniq.take(30)

    return nil if terms.empty? || results.empty?

    match_counts = []
    results.each do |r|
      hay = "#{r["title"]} #{r["snippet"]}".downcase
      matches = terms.count { |t| hay.include?(t) }
      match_counts << matches
    end

    # Normalize to 0..100.
    avg_matches = match_counts.sum.to_f / match_counts.length
    max_matches = match_counts.max || 0

    # If many results have high match counts, risk is higher.
    raw = (avg_matches * 10) + (max_matches * 2)
    [[raw.round, 0].max, 100].min
  end
end

