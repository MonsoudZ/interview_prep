class BehavioralContent
  TOPICS = %w[ownership incidents conflict mentoring tradeoffs].freeze
  SECTIONS = %w[situation task actions results reflection short_version].freeze
  LABELS = { "situation" => "Situation and stakes", "task" => "Your responsibility", "actions" => "Your specific actions",
    "results" => "Outcomes and evidence", "reflection" => "Reflection and learning", "short_version" => "Two-minute opening" }.freeze
  FILES = %w[answer.md preparation.md].freeze
  def self.entries
    Dir.glob(Rails.root.join("../../curriculum/behavioral/*/exercise.json")).sort.map { |path| JSON.parse(File.read(path)) }
  end
  def self.find(exercise)
    return unless exercise.track == "behavioral"
    entries.find { |item| item.fetch("slug") == exercise.slug && item.fetch("version") == exercise.version }
  end
  def self.review(exercise)
    entry = find(exercise)
    return unless entry
    JSON.parse(File.read(Rails.root.join("../../curriculum/behavioral", entry.fetch("topic"), "review.json")))
  end
  def self.story_markdown(story)
    (["# #{story.title}", "Prepared story · version #{story.lock_version}. This is prior preparation, not the rehearsed answer."] +
      SECTIONS.flat_map { |key| ["## #{LABELS.fetch(key)}", story.sections.fetch(key)] }).join("\n\n") + "\n"
  end
  def self.context(story)
    { "story_id" => story.id, "story_version" => story.lock_version, "title" => story.title, "captured_at" => Time.current.iso8601,
      "prior_preparation" => true }
  end
end
