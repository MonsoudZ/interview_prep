class ExerciseCatalog
  CONTENT = {
    "repository-events" => {
      summary: "Build create, list, filter, and lookup endpoints for repository events. Handle validation and HTTP errors against 12 integration tests.",
      difficulty: "Senior · implementation", skills: ["Rails API", "Validation", "HTTP contracts"],
      tools: ["Ruby editor", "Isolated Rails runner", "12 integration tests", "Guided hints", "Submission self-review"]
    },
    "merge-intervals" => {
      summary: "Merge unsorted, overlapping intervals without mutating the input. Explain correctness, edge cases, and time complexity.",
      difficulty: "Medium · algorithms", skills: ["Sorting", "Intervals", "Complexity"],
      tools: ["Ruby editor", "Guided hints", "Submission self-review"], limitation: "Ruby execution is not available yet. Save and explain your solution."
    },
    "webhook-delivery" => {
      summary: "Design durable webhook delivery with retries, idempotency, tenant fairness, and a plan for endpoint outages.",
      difficulty: "Senior · architecture", skills: ["Queues", "Reliability", "Multi-tenancy"],
      tools: ["Markdown editor", "Guided hints", "Submission self-review"], limitation: "Design notes only. Diagramming, voice, and AI review are not available yet."
    }
  }.freeze

  def self.details(exercise)
    if exercise.slug == "webhook-delivery" && exercise.version == 2
      return CONTENT.fetch("webhook-delivery").merge(brief: exercise.brief,
        tools: ["Architecture canvas", "Structured design notes", "SVG / Markdown export", "Guided hints", "Submission self-review"],
        limitation: "Voice, conversational interviewing, and automated design review are not available yet.",
        difficulty_note: "Editorial practice level, not a calibrated interview score.")
    end
    if exercise.slug == "merge-intervals" && exercise.version == 2
      return CONTENT.fetch("merge-intervals").except(:limitation).merge(brief: exercise.brief,
        tools: ["Ruby editor", "Isolated Ruby runner", "6 visible + 6 additional test groups", "Guided hints", "Submission self-review"],
        difficulty_note: "Editorial practice level, not a calibrated interview score.")
    end
    manifest = RailsCurriculum.find(exercise.slug, exercise.version)
    if manifest
      return manifest.slice("summary", "difficulty", "skills").symbolize_keys.merge(
        brief: exercise.brief, tools: ["Ruby editor", "Isolated Rails runner", "12 test groups", "Guided hints", "Submission self-review"],
        difficulty_note: "Editorial practice level, not a calibrated interview score.")
    end
    CONTENT.fetch(exercise.slug) do
      { summary: exercise.brief.split("\n\n").first, difficulty: "Uncalibrated", skills: [], tools: ["Saved workspace"] }
    end.merge(brief: exercise.brief, difficulty_note: "Editorial practice level, not a calibrated interview score.")
  end
end
