root = Rails.root.join("../..").expand_path
template = root.join("experiments/rails-runtime/template")
files = Dir.glob(template.join("**/*")).select { |path| File.file?(path) && !path.include?("/log/") }.to_h { |path|
  [Pathname.new(path).relative_path_from(template).to_s, File.read(path)]
}
ExerciseVersion.find_or_create_by!(slug: "repository-events", version: 1) do |exercise|
  exercise.title = "Repository Events API"
  exercise.track = "rails"
  exercise.operation = "rails.events.v1"
  exercise.duration_minutes = 50
  exercise.brief = File.read(template.join("BRIEF.md"))
  exercise.starter_files = files
end
# Published repositories are immutable; references/review notes never enter candidate source.
Dir.glob(root.join("curriculum/rails/*/exercise.json")).sort.each do |manifest|
  metadata = JSON.parse(File.read(manifest))
  starter = Pathname.new(manifest).dirname.join("starter")
  overlay = Dir.glob(starter.join("**/*")).select { |path| File.file?(path) }.to_h { |path|
    [Pathname.new(path).relative_path_from(starter).to_s, File.read(path)]
  }
  ExerciseVersion.find_or_create_by!(slug: metadata.fetch("slug"), version: metadata.fetch("version")) do |exercise|
    exercise.title = metadata.fetch("title")
    exercise.track = "rails"
    exercise.operation = metadata.fetch("operation")
    exercise.duration_minutes = metadata.fetch("duration_minutes")
    exercise.brief = overlay.fetch("BRIEF.md")
    exercise.starter_files = files.merge(overlay)
  end
end
ExerciseVersion.find_or_create_by!(slug: "merge-intervals", version: 1) do |exercise|
  exercise.title = "Merge Busy Intervals"
  exercise.track = "ruby"
  exercise.duration_minutes = 35
  exercise.brief = "Implement merge_intervals(intervals). Merge unsorted, overlapping or touching integer intervals into ascending disjoint intervals. Do not mutate the input. Empty input is allowed; endpoints may be negative and start <= finish. Up to 100,000 intervals.\n\nExample: [[5,7],[1,3],[3,4],[9,12]] => [[1,4],[5,7],[9,12]].\n\nExplain correctness, complexity, and edge cases. Follow-up: what changes when input is already sorted?\n\nThis foundation supports saved code and timed sessions. The Ruby execution runner and interviewer are not connected yet."
  exercise.starter_files = { "solution.rb" => "def merge_intervals(intervals)\n  # Your implementation\nend\n" }
end
ExerciseVersion.find_or_create_by!(slug: "webhook-delivery", version: 1) do |exercise|
  exercise.title = "Reliable Webhook Delivery"
  exercise.track = "system_design"
  exercise.duration_minutes = 50
  exercise.brief = "Design a service delivering repository events to customer-configured HTTPS endpoints. Customers subscribe endpoints and inspect outcomes.\n\nPractice assumptions: 1,000 incoming events/second, 10,000 peak; average 2 KB payload; average fan-out 3; 10,000 endpoints. Healthy endpoints: 95% of first attempts start within 10 seconds. Accepted events survive one machine failure. Duplicate delivery is allowed; no global ordering requirement. Retry transient failures up to 24 hours, retain metadata for 30 days. Start in one region.\n\nDiscuss requirements, APIs, data model, durable acceptance, retries, idempotency, tenant fairness, destination security, and observability.\n\nFailure scenario: a large customer's endpoint is unavailable for two hours.\n\nThis foundation saves design notes and supports timing. The diagram canvas, voice interviewer, and AI evaluation are not connected yet."
  exercise.starter_files = { "notes.md" => "# Requirements\n\n# Capacity estimates\n\n# Architecture and data flow\n\n# APIs and data model\n\n# Failure handling and tradeoffs\n" }
end

ruby_starter = root.join("curriculum/ruby/merge-intervals/starter")
ExerciseVersion.find_or_create_by!(slug: "merge-intervals", version: 2) do |exercise|
  exercise.title = "Merge Busy Intervals"
  exercise.track = "ruby"
  exercise.operation = "ruby.intervals.v1"
  exercise.duration_minutes = 35
  exercise.brief = File.read(ruby_starter.join("BRIEF.md"))
  exercise.starter_files = Dir.glob(ruby_starter.join("**/*")).select { |path| File.file?(path) }.to_h { |path|
    [Pathname.new(path).relative_path_from(ruby_starter).to_s, File.read(path)]
  }
end

# Ruby exercises published with a manifest. Hidden tests and references never enter candidate source.
Dir.glob(root.join("curriculum/ruby/*/exercise.json")).sort.each do |manifest|
  metadata = JSON.parse(File.read(manifest))
  starter = Pathname.new(manifest).dirname.join("starter")
  starter_files = Dir.glob(starter.join("**/*")).select { |path| File.file?(path) }.to_h { |path|
    [Pathname.new(path).relative_path_from(starter).to_s, File.read(path)]
  }
  ExerciseVersion.find_or_create_by!(slug: metadata.fetch("slug"), version: metadata.fetch("version")) do |exercise|
    exercise.title = metadata.fetch("title")
    exercise.track = "ruby"
    exercise.operation = metadata.fetch("operation")
    exercise.duration_minutes = metadata.fetch("duration_minutes")
    exercise.brief = starter_files.fetch("BRIEF.md")
    exercise.starter_files = starter_files
  end
end

design_starter = root.join("curriculum/system_design/webhook-delivery/starter")
ExerciseVersion.find_or_create_by!(slug: "webhook-delivery", version: 2) do |exercise|
  exercise.title = "Reliable Webhook Delivery"
  exercise.track = "system_design"
  exercise.duration_minutes = 50
  exercise.brief = File.read(design_starter.join("BRIEF.md"))
  exercise.starter_files = Dir.glob(design_starter.join("*")).select { |path| File.file?(path) }.to_h { |path|
    [File.basename(path), File.read(path)]
  }
end

BehavioralContent.entries.each do |entry|
  ExerciseVersion.find_or_create_by!(slug: entry.fetch("slug"), version: entry.fetch("version")) do |exercise|
    exercise.title = entry.fetch("title")
    exercise.track = "behavioral"
    exercise.duration_minutes = entry.fetch("duration_minutes")
    exercise.brief = File.read(root.join("curriculum/behavioral", entry.fetch("topic"), "BRIEF.md"))
    exercise.starter_files = { "answer.md" => "# Rehearsed answer\n\n## Situation and stakes\n\n## My responsibility\n\n## Actions and decisions\n\n## Outcomes and evidence\n\n## Reflection and learning\n",
      "preparation.md" => "# Preparation\n\nNo story-bank example was imported. Write the actual rehearsal in answer.md.\n" }
  end
end
