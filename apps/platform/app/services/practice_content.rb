require "yaml"

class PracticeContent
  def self.for(exercise)
    curriculum = RailsCurriculum.review(exercise)
    return curriculum if curriculum
    # Only published exercise identities choose content files; request paths never do.
    name = { "repository-events" => "rails", "merge-intervals" => "ruby", "webhook-delivery" => "system_design" }[exercise.slug]
    return nil unless name && (exercise.version == 1 || (%w[ruby system_design].include?(name) && exercise.version == 2))
    content_version = %w[ruby system_design].include?(name) && exercise.version == 2 ? 2 : 1
    YAML.safe_load_file(Rails.root.join("config/practice/#{name}-v#{content_version}.yml"), permitted_classes: [], aliases: false)
  end

  def self.present(session)
    content = self.for(session.exercise_version)
    return { available: false, hints: [] } unless content
    revealed = session.hint_reveals.order(:position).to_a
    { available: true, content_version: content.fetch("version"),
      hints: revealed.map { |record| content.fetch("hints").fetch(record.position).merge("revealed_at" => record.created_at) },
      total_hints: content.fetch("hints").length,
      can_reveal: session.mode == "guided" && session.status != "submitted" && revealed.length < content.fetch("hints").length }
  end
end
