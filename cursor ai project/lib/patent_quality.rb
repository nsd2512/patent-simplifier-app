module PatentQuality
  REQUIRED_KEYS = [
    "applicationType",
    "title",
    "summary",
    "howItWorks",
    "keyComponents",
    "processSteps"
  ].freeze

  def self.assess_idea(data)
    data = (data || {}).transform_keys(&:to_s)
    application_type = (data["applicationType"] || "utility").to_s

    missing = REQUIRED_KEYS.filter_map { |k| data[k].to_s.strip.empty? ? k : nil }
    missing = missing.reject { |k| k == "keyComponents" || k == "processSteps" } # handled by separate rubric

    components = split_lines(data["keyComponents"])
    steps = split_lines(data["processSteps"])
    summary = (data["summary"] || "").to_s.strip
    how_it_works = (data["howItWorks"] || "").to_s.strip
    title = (data["title"] || "").to_s.strip

    score = 0
    feedback = []
    checklist = []

    # Basic presence
    if title.empty?
      checklist << "Add a clear, specific invention title."
    else
      score += 12
    end

    if summary.length >= 120
      score += 22
    else
      checklist << "Expand the Summary (aim for 3-6 sentences with problem + solution)."
      score += [summary.length / 10, 20].min.round
    end

    if how_it_works.length >= 250
      score += 28
    else
      checklist << "Expand How it works (aim for an enabling description of the invention)."
      score += [how_it_works.length / 10, 26].min.round
    end

    # Components & steps
    if components.length >= 3
      score += 18
    else
      checklist << "Add at least 3 key components (e.g., Module A, Sensor B, Controller C)."
      score += [components.length * 4, 16].min.round
    end

    if steps.length >= 2
      score += 16
    else
      checklist << "Add at least 2 process steps (what happens first/next)."
      score += [steps.length * 5, 14].min.round
    end

    # Specificity signals
    specificity = 0
    specificity += 6 if /[0-9]/.match?(summary + " " + how_it_works) # parameters/values
    specificity += 6 if /(sensor|module|controller|processor|memory|receiver|transmitter|database|engine|filter)/i.match?(summary + " " + how_it_works)
    specificity += 6 if /(wherein|configured|comprising|receiving|transmitting|determining)/i.match?(how_it_works)
    specificity += 6 if /\b(near|during|after|before|based on|using)\b/i.match?(how_it_works)
    specificity = [specificity, 18].min

    score += specificity

    # Clamp and grade
    score = [[score, 0].max, 100].min
    grade =
      if score >= 80
        "Strong candidate (still not a legal novelty determination)"
      elsif score >= 55
        "Promising but needs more enabling detail"
      else
        "Too thin for a strong filing; add structure/components"
      end

    feedback << grade
    feedback << "This is a heuristic screen to improve filing readiness, not legal advice."

    # Supplemental guidance based on missing rubric pieces.
    if missing.any?
      feedback << "Missing/empty fields: #{missing.join(", ")}"
    end

    if application_type == "provisional"
      checklist.unshift("For a US provisional, include as much detail as possible (enablement > brevity).")
    else
      checklist.unshift("For a US utility application, claims will be generated as starting points—verify each limitation.")
    end

    return {
      "score" => score,
      "grade" => grade,
      "feedback" => feedback,
      "checklist" => checklist.uniq
    }
  end

  def self.split_lines(value)
    return [] if value.nil?
    v = value.to_s
    v.split(/\r?\n/).map(&:strip).reject(&:empty?)
  end
end

