# No database writes: use published curriculum and the production guidance selector.
require_relative "../../../apps/platform/config/environment"
root = Rails.root.join("../..")
packets = %w[lru-cache rate-limiter].flat_map do |slug|
  base = root.join("curriculum/ruby", slug)
  exercise = JSON.parse(File.read(base.join("exercise.json")))
  exercise["brief"] = File.read(base.join("starter/BRIEF.md"))
  review = JSON.parse(File.read(base.join("review.json")))
  reference = File.read(base.join("reference/solution.rb"))
  broken = if slug == "lru-cache"
    reference.sub("value = @entries.delete(key)\n    @entries[key] = value", "@entries[key]")
  else
    reference.sub("now - stamps.first >= @window", "now - stamps.first > @window")
  end
  raise "Mutation did not apply" if broken == reference
  defect_line = broken.lines.index { |line| line != reference.lines[broken.lines.index(line)] } + 1
  [["reference", reference], ["defect", broken]].map do |variant, source|
    # Author expectations: which criterion the planted defect violates, where it is, and which source
    # criteria must stay independent of it. Process criteria cannot be observed from source alone.
    expect = { "source_criteria" => %w[correctness] + (slug == "lru-cache" ? %w[complexity boundaries] : %w[memory boundaries]),
      "process_criteria" => %w[verification],
      "defect" => variant == "defect" ? { "criterion" => "correctness", "path" => "solution.rb", "line" => defect_line } : nil }
    { "case" => "#{slug}-#{variant}", "expect" => expect, "packet" => {
      "prompt_version" => ReviewPacket::PROMPT_VERSION, "revision" => Digest::SHA256.hexdigest(source),
      "exercise" => exercise, "rubric" => review.fetch("criteria"), "follow_up" => review["follow_up"],
      "reviewer_guidance" => ReviewGuidance.for("ruby"), "files" => { "solution.rb" => source },
      "reference_alternative" => nil, "assistance" => [], "mode" => "guided", "practice_focus" => nil,
      "rework" => nil, "executions" => [],
      "limitations" => ["No voice or follow-up transcript is included in this code/design review packet. Do not infer communication, prompting, or independence from code alone.", "No execution logs are included. This is a local evaluator fixture, not personal practice history."]
    } }
  end
end
design_source = <<~NOTES
  The service starts in one region. Each accepted event must survive one machine failure.
  Store events in a primary database with a synchronous replica on a different machine.
  Return HTTP 202 only after the event transaction is durably committed on both machines.
  If either required commit acknowledgement is unavailable, return a retryable error instead of 202.
  Failover promotes only a replica that contains every acknowledged commit; do not promote stale state.
  A client retry may create a duplicate event; duplicates are explicitly allowed in this exercise.
  Multiple regions and exactly-once processing are outside the published contract.
NOTES
%w[reference defect].each do |variant|
  source = variant == "reference" ? design_source : design_source.sub(
    "Return HTTP 202 only after the event transaction is durably committed on both machines.",
    "Return HTTP 202 immediately after placing the event in this process's memory; persist it asynchronously later.")
  defect_line = source.lines.index { |line| line.include?("Return HTTP 202") } + 1
  expect = { "source_criteria" => %w[durability scope], "process_criteria" => [],
    "defect" => variant == "defect" ? { "criterion" => "durability", "path" => "notes.md", "line" => defect_line } : nil }
  packets << { "case" => "durable-intake-#{variant}", "expect" => expect, "packet" => {
    "prompt_version" => ReviewPacket::PROMPT_VERSION, "revision" => Digest::SHA256.hexdigest(source),
    "exercise" => { "slug" => "evaluation-durable-intake", "version" => 1, "track" => "system_design",
      "title" => "Evaluation fixture: durable event intake",
      "brief" => "Explain acceptance durability for an event API in one region. An event acknowledged with HTTP 202 must survive one machine failure. Reject or defer acceptance when durability is unavailable. Duplicate events are allowed. No multi-region, exactly-once, delivery-worker, or throughput requirement is imposed. Assess only the acceptance path described in notes.md." },
    "rubric" => [{ "id" => "durability", "title" => "Acknowledged events survive one machine failure", "target" => "Acknowledgement follows durable storage that survives one machine failure; failures before that point do not receive success." },
                 { "id" => "scope", "title" => "Appropriate scope", "target" => "A coherent single-region approach without unnecessary multi-region or exactly-once machinery." }],
    "follow_up" => nil, "reviewer_guidance" => ReviewGuidance.for("system_design"),
    "files" => { "notes.md" => source }, "reference_alternative" => nil, "assistance" => [],
    "mode" => "guided", "practice_focus" => nil, "rework" => nil, "executions" => [],
    "limitations" => ["No voice or follow-up transcript is included in this code/design review packet. Do not infer communication, prompting, or independence from the design alone.", "Author-created design regression fixture; no running system is involved."]
  } }
end
puts JSON.generate(packets)
