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
  defect_line = broken.lines.zip(reference.lines).index { |mutated, original| mutated != original } + 1
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
      "rework" => nil, "executions" => [], "follow_up_answers" => [],
      "limitations" => [ReviewPacket::NO_FOLLOW_UP_LIMITATION, "No execution logs are included. This is a local evaluator fixture, not personal practice history."]
    } }
  end
end
# LRU reference with a completed follow-up round on the same revision. The verification criterion is about the
# candidate's process, so it can only be rated from the typed answer: the correct answer predicts a failing
# sequence that matches what the source does and must be rated at target; the contradicting answer claims a
# `get` leaves recency unchanged (the reference refreshes it) and that tests ran before any prediction, so it
# must be rated below target with a citation into follow-up/verification.md. Source criteria stay at target.
lru = packets.find { |case_record| case_record["case"] == "lru-cache-reference" }
lru_probe = lru.dig("packet", "rubric").find { |criterion| criterion["id"] == "verification" }.fetch("probe")
lru_answers = {
  "correct" => <<~ANSWER,
    Before running the suite I wrote the expected keys for capacity 2: put a, put b, get a, put c.
    The get moves a to most recent, so c evicts b and keys should be [a, c]; a cache whose get did not refresh would evict a instead.
    For an off-by-one in the eviction check I used capacity 1: put a, put b must leave keys == [b]; a check written as size >= capacity would evict on the first put and leave the cache empty.
    The 100,000-operation groups would time out only if get or put scanned the entries; a wrong answer in the small groups means recency is off, a timeout means a linear step crept in.
  ANSWER
  "contradicts" => <<~ANSWER,
    Only put changes the recency order; get just reads the value and leaves the order alone, so for capacity 2 the sequence put a, put b, get a, put c evicts a and leaves keys == [b, c].
    I ran the full suite first and then reasoned backwards from whichever group failed rather than predicting a sequence up front.
  ANSWER
}
lru_answers.each do |variant, answer|
  answers = [{ "criterion_id" => "verification", "path" => "follow-up/verification.md", "prompt" => lru_probe, "status" => "answered",
    "answer" => answer, "truncated" => false, "round_id" => "evaluation-fixture-round", "completed_at" => "2026-10-21T00:00:00Z" }]
  defect_line = variant == "contradicts" ? 1 : nil
  expect = { "source_criteria" => %w[correctness complexity boundaries], "process_criteria" => [],
    "answered_process_criteria" => %w[verification],
    "defect" => defect_line && { "criterion" => "verification", "path" => "follow-up/verification.md", "line" => defect_line } }
  packets << { "case" => "lru-cache-followup-#{variant}", "expect" => expect, "packet" => lru["packet"].merge(
    "files" => lru["packet"]["files"].merge(ReviewPacket.follow_up_files(answers)), "follow_up_answers" => answers,
    "limitations" => [ReviewPacket::FOLLOW_UP_LIMITATION, "No execution logs are included. This is a local evaluator fixture, not personal practice history."]) }
end
# Rails track: one published exercise whose candidate snapshot is the editable starter files with the
# controller replaced. The defect lets a query parameter choose the organization, which the brief forbids
# ("Query parameters cannot select another organization"; identity comes only from the authenticated user).
rails_base = root.join("curriculum/rails/tenant-projects")
rails_exercise = JSON.parse(File.read(rails_base.join("exercise.json")))
rails_exercise["track"] ||= "rails"
rails_exercise["brief"] = File.read(rails_base.join("starter/BRIEF.md"))
rails_review = JSON.parse(File.read(rails_base.join("review.json")))
controller = "app/controllers/projects_controller.rb"
starter_files = Dir.glob(rails_base.join("starter/**/*.rb")).sort.to_h { |path|
  [Pathname.new(path).relative_path_from(rails_base.join("starter")).to_s, File.read(path)]
}.select { |path, _| Workspace.editable?(path) }
rails_reference = File.read(rails_base.join("reference", controller))
rails_broken = rails_reference.sub("Project.where(organization_id: @user.organization_id)",
  "Project.where(organization_id: params[:organization_id].presence || @user.organization_id)")
raise "Mutation did not apply" if rails_broken == rails_reference
rails_defect_line = rails_broken.lines.zip(rails_reference.lines).index { |mutated, original| mutated != original } + 1
[["reference", rails_reference], ["defect", rails_broken]].each do |variant, source|
  files = starter_files.merge(controller => source)
  expect = { "source_criteria" => %w[boundary authorization safe_updates], "process_criteria" => %w[debugging],
    "defect" => variant == "defect" ? { "criterion" => "boundary", "path" => controller, "line" => rails_defect_line } : nil }
  packets << { "case" => "tenant-projects-#{variant}", "expect" => expect, "packet" => {
    "prompt_version" => ReviewPacket::PROMPT_VERSION, "revision" => Digest::SHA256.hexdigest(JSON.generate(files)),
    "exercise" => rails_exercise, "rubric" => rails_review.fetch("criteria"), "follow_up" => rails_review["follow_up"],
    "reviewer_guidance" => ReviewGuidance.for("rails"), "files" => files,
    "reference_alternative" => nil, "assistance" => [], "mode" => "guided", "practice_focus" => nil,
    "rework" => nil, "executions" => [], "follow_up_answers" => [],
    "limitations" => [ReviewPacket::NO_FOLLOW_UP_LIMITATION, "No execution logs are included. This is a local evaluator fixture, not personal practice history."]
  } }
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
    "mode" => "guided", "practice_focus" => nil, "rework" => nil, "executions" => [], "follow_up_answers" => [],
    "limitations" => ["No voice or follow-up transcript is included in this code/design review packet. Do not infer communication, prompting, or independence from the design alone.", "Author-created design regression fixture; no running system is involved."]
  } }
end
puts JSON.generate(packets)
