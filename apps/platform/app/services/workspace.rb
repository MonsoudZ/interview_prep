require "digest"
class Workspace
  class Invalid < StandardError; end
  def self.editable?(path, exercise = nil)
    return BehavioralContent::FILES.include?(path) if exercise&.track == "behavioral"
    if exercise&.track == "system_design"
      return exercise.version >= 2 ? DesignDocument::FILES.include?(path) : path == "notes.md"
    end
    path.is_a?(String) && path.length <= 240 && path.match?(/\A[A-Za-z0-9_.\/-]+\z/) &&
      !path.split("/", -1).any? { |part| ["", ".", ".."].include?(part) } &&
      ((path.start_with?("app/") && path.end_with?(".rb")) || %w[config/routes.rb db/schema.rb notes.md solution.rb].include?(path))
  end

  def self.validate!(files, exercise)
    raise Invalid, "Expected a file map" unless files.is_a?(Hash) && files.length.between?(1, 128)
    if exercise.track == "system_design" && exercise.version >= 2
      raise Invalid, "Keep all design sections and diagram together" unless files.keys.sort == DesignDocument::FILES.sort
      DesignDocument.validate!(files.fetch("diagram.json"))
    end
    if exercise.track == "behavioral"
      raise Invalid, "Keep the behavioral answer and preparation together" unless files.keys.sort == BehavioralContent::FILES.sort
    end
    total = 0
    files.each do |path, text|
      permitted = %w[system_design behavioral].include?(exercise.track) ? editable?(path, exercise) : exercise.track == "ruby" ? path == "solution.rb" : editable?(path) && !%w[solution.rb notes.md].include?(path)
      raise Invalid, "File path or content is invalid" unless permitted && text.is_a?(String) && text.valid_encoding?
      total += text.bytesize
    end
    raise Invalid, "Workspace exceeds 1 MiB" if total > 1024 * 1024
    files
  end

  def self.revision(files)
    Digest::SHA256.hexdigest(JSON.generate(files.sort.to_h.transform_values { |text| Digest::SHA256.hexdigest(text.encode("UTF-8")) }))
  end

  def self.save!(session, files)
    validate!(files, session.exercise_version)
    digest = revision(files)
    snapshot = session.source_snapshots.find_or_create_by!(revision: digest) { |record| record.files = files }
    session.update!(current_revision: snapshot.revision)
    snapshot
  end
end
