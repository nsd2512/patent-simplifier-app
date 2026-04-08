require "cgi"

module PatentDrafting
  def self.generate_draft(data)
    data = (data || {}).transform_keys(&:to_s)
    application_type = (data["applicationType"] || "utility").to_s

    title = (data["title"] || "").to_s.strip
    summary = (data["summary"] || "").to_s.strip
    how_it_works = (data["howItWorks"] || "").to_s.strip
    key_components = split_lines(data["keyComponents"])
    process_steps = split_lines(data["processSteps"])
    external_sources = split_lines(data["externalSources"]).map { |s| s.strip }
    use_cases = split_lines(data["useCases"])

    # Derive small structured bits for diagrams/search.
    diagram_mermaid = build_mermaid(key_components, process_steps)
    claims = application_type == "utility" ? generate_claims(title, key_components, process_steps) : []
    search_payload = build_search_payload(title, summary, how_it_works, key_components, process_steps, external_sources)

    html = build_html(
      application_type,
      title,
      summary,
      how_it_works,
      key_components,
      process_steps,
      use_cases,
      claims,
      diagram_mermaid,
      external_sources
    )

    {
      "applicationType" => application_type,
      "draftHtml" => html,
      "mermaid" => diagram_mermaid,
      "claims" => claims,
      "search_payload" => search_payload
    }
  end

  def self.split_lines(value)
    return [] if value.nil?
    v = value.to_s
    v.split(/\r?\n/).map(&:strip).reject(&:empty?)
  end

  def self.bullets(list)
    list.map { |x| "<li>#{CGI.escapeHTML(x)}</li>" }.join
  end

  def self.safe_text(s)
    CGI.escapeHTML(s.to_s)
  end

  def self.build_mermaid(components, steps)
    components = components.dup
    steps = steps.dup

    # Keep it readable and stable.
    components = components.take(10)
    steps = steps.take(8)

    component_nodes =
      components.each_with_index.map do |c, i|
        { id: "C#{i + 1}", label: c }
      end

    step_nodes =
      steps.each_with_index.map do |s, i|
        { id: "S#{i + 1}", label: s }
      end

    # If user provided no components/steps, provide placeholders.
    component_nodes = [{ id: "C1", label: "Key component(s) described by the user" }] if component_nodes.empty?
    step_nodes = [{ id: "S1", label: "Process step(s) described by the user" }] if step_nodes.empty?

    lines = []
    lines << "flowchart TD"
    lines << "  IN[Idea / Input] --> D1[Detailed operation]"

    # Component cluster -> processing
    component_nodes.each_with_index do |node, idx|
      connector = idx == 0 ? "D1" : "C#{idx}"
      lines << "  C#{idx + 1}[#{node[:label].gsub(/[\r\n]/, ' ')}]"
      lines << "  #{connector} --> C#{idx + 1}" if idx >= 1
    end

    lines << "  D1 --> S1"
    step_nodes.each_with_index do |node, idx|
      lines << "  #{node[:id]}[#{node[:label].gsub(/[\r\n]/, ' ')}]"
      lines << "  S#{idx + 1} --> S#{idx + 2}" if idx + 1 < step_nodes.length
    end

    lines << "  S#{step_nodes.length}[Outcome / Result]"
    lines
      .join("\n")
      .gsub(/[ ]{2,}/, " ")
  end

  def self.generate_claims(title, components, steps)
    title = title.empty? ? "this invention" : title
    components = components.take(12)
    steps = steps.take(6)

    component_phrases =
      if components.any?
        components.map { |c| CGI.escapeHTML(c) }
      else
        ["a processor", "a memory", "an interface"]
      end

    # Provide a conservative, editable starter set.
    claim1 = "1. An apparatus configured to realize #{title}, the apparatus comprising: #{component_phrases.join(", ")}, and wherein the apparatus is configured to carry out the process of the invention."

    step_ref = steps.any? ? steps.first : "a first process step"
    step_ref2 = steps.length >= 2 ? steps[1] : "a subsequent process step"

    claim2 = "2. The apparatus of claim 1, wherein #{claim_fragment_from_step(step_ref)}."
    claim3 = "3. The apparatus of claim 1, wherein #{claim_fragment_from_step(step_ref2)}."

    disclaimer =
      [
        "CLAIMS NOTICE: These are automatically generated starter claims for editing. Verify each limitation with your disclosure and consult a registered patent attorney/agent before filing."
      ].join(" ")

    # Return only claim strings; disclaimers go in HTML.
    [claim1, claim2, claim3, disclaimer]
  end

  def self.claim_fragment_from_step(step_text)
    s = step_text.to_s.strip
    # Try to convert "Step: X" to a clause.
    s = s.sub(/^(step|process|operation)\s*[:\-]\s*/i, "")
    # Ensure it reads reasonably.
    s = "executing #{s.downcase}" unless s =~ /\b(configured|executing|determining|receiving|transmitting|processing|applying|storing|generating)\b/i
    s.gsub(/\s+/, " ")
  end

  def self.build_search_payload(title, summary, how_it_works, components, steps, external_sources)
    query_core = [
      title,
      summary,
      how_it_works,
      components.join(" "),
      steps.join(" ")
    ].join(" ")

    # Keep to manageable size and remove obvious markup.
    query_core = query_core.gsub(/[^\w\s\-.,:;()]/, " ")
    query_core = query_core.squeeze(" ").strip

    # Create multiple site-restricted queries to improve coverage.
    keyword_phrases = [
      title,
      components.first,
      steps.first
    ].compact.reject(&:empty?)

    {
      "queryCore" => query_core,
      "externalSources" => external_sources,
      "queryTerms" => keyword_phrases.take(3).concat(["patent", "application", "USPTO", "system", "method"]).uniq.take(8)
    }
  end

  def self.build_html(application_type, title, summary, how_it_works, key_components, process_steps, use_cases, claims, diagram_mermaid, external_sources)
    title = title.empty? ? "Untitled invention" : title

    # Keep HTML simple and printable.
    css = <<~CSS
      body { font-family: Arial, Helvetica, sans-serif; margin: 24px; color: #111; }
      h1 { font-size: 20px; }
      h2 { font-size: 14px; margin-top: 22px; }
      h3 { font-size: 12px; margin-top: 16px; }
      .muted { color: #444; font-size: 12px; }
      .pagehint { border: 1px solid #ddd; padding: 10px; margin: 12px 0; background: #fafafa; }
      ul { margin-top: 8px; }
      li { margin: 4px 0; }
      pre { white-space: pre-wrap; word-wrap: break-word; background: #f6f6f6; padding: 10px; border-radius: 6px; }
      .mermaid { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; font-size: 12px; }
      @media print { body { margin: 0.75in; } .no-print { display: none; } }
    CSS

    claim_disclaimer = claims[3].to_s
    claim_texts = claims[0, 3].compact

    external_sources_items_html =
      if external_sources.any?
        external_sources.map { |s| "<li>#{safe_text(s)}</li>" }.join
      else
        "<li class='muted'>No external sources provided.</li>"
      end

    desc_details = []
    desc_details << "<h3>Key components (from user input)</h3><ul>#{bullets(key_components)}</ul>" if key_components.any?
    desc_details << "<h3>Process / operation (from user input)</h3><ol>#{process_steps.map { |s| "<li>#{safe_text(s)}</li>" }.join}</ol>" if process_steps.any?
    desc_details << "<h3>Embodiments (starter placeholders)</h3>"
    desc_details << "<p>Provide additional embodiments, variations, and implementation details sufficient to enable a person skilled in the art to make and use the invention.</p>"
    desc_details << "<ul><li>Embodiment 1: Include specific structure/logic and how each component interacts.</li><li>Embodiment 2: Include alternative component configurations and parameter ranges.</li><li>Embodiment 3: Include alternative operating conditions and performance considerations.</li></ul>"

    use_cases_html = if use_cases.any?
      "<h3>Use cases / benefits (from user input)</h3><ul>#{bullets(use_cases)}</ul>"
    else
      ""
    end

    brief_drawings =
      "<p>FIG. 1: Block diagram illustrating functional components and data/control flow (see Mermaid source).<br/>FIG. 2: Optional variation diagram.</p>"

    # NOTE: This is not legal template; it is a structured writing scaffold.
    spec_header = if application_type == "provisional"
      "<div class='pagehint'><b>US Provisional Application Draft (structured scaffold).</b> This is a writing aid. A provisional does not include formal claims, but it should fully enable the invention.</div>"
    else
      "<div class='pagehint'><b>US Utility Application Draft (structured scaffold).</b> This is a writing aid and includes starter claims for editing.</div>"
    end

    html = <<~HTML
      <!doctype html>
      <html>
        <head>
          <meta charset="utf-8" />
          <title>Patent Draft - #{CGI.escapeHTML(title)}</title>
          <style>#{css}</style>
        </head>
        <body>
          <div class="no-print muted">Generated by Patent Assistant (heuristic scaffold). Not legal advice.</div>
          <h1>#{CGI.escapeHTML(title)}</h1>
          #{spec_header}

          <h2>Application Type</h2>
          <p>#{CGI.escapeHTML(application_type.to_s.upcase)} (US)</p>

          <h2>Abstract</h2>
          <p>#{safe_text(summary.empty? ? how_it_works[0, 500] : summary)}</p>

          <h2>Background</h2>
          <p>Describe the technical field, problems in the art, and motivations for the invention. Explain what is not adequately addressed by existing approaches.</p>

          <h2>Summary of the Invention</h2>
          <p>#{safe_text(summary)}</p>

          <h2>Brief Summary of Drawings</h2>
          #{brief_drawings}

          <h2>Detailed Description</h2>
          #{desc_details.join("\n")}
          #{use_cases_html}

          <h2>Block Diagram (Mermaid Source)</h2>
          <p class="muted">Render this Mermaid source to create your FIGURE. You can paste it into a Mermaid renderer.</p>
          <pre class="mermaid">#{CGI.escapeHTML(diagram_mermaid)}</pre>

          #{ if application_type == "utility"
            "<h2>Claims (starter set for editing)</h2>" \
            "<div class='pagehint'>#{safe_text(claim_disclaimer)}</div>" \
            "<div>#{claim_texts.each_with_index.map { |c, i| "<p><b>#{i + 1}.</b> #{safe_text(c)}</p>" }.join}</div>"
          else
            ""
          end }

          <h2>External Sources (user provided)</h2>
          <p class="muted">Included to guide your prior-art search and drafting consistency.</p>
          <ul>#{external_sources_items_html}</ul>

          <div class="muted" style="margin-top: 26px;">
            DISCLAIMER: This draft is generated from user-provided text and heuristic templates. It is not legal advice and does not ensure patentability or compliance with USPTO requirements.
          </div>
        </body>
      </html>
    HTML

    html
  end
end

