# Trusted, published identities resolve local curriculum files; never request paths.
class RailsCurriculum
  def self.entries
    Dir.glob(Rails.root.join("../../curriculum/rails/*/exercise.json")).sort.map { |path| JSON.parse(File.read(path)) }
  end

  def self.find(slug, version)
    entries.find { |entry| entry.fetch("slug") == slug && entry.fetch("version") == version }
  end

  ORDER = %w[repository-events tenant-projects idempotent-checkout delivery-retries activity-feed support-escalations invoice-amendments safe-backfill].freeze

  def self.reference(exercise)
    root = if exercise.slug == "repository-events" && exercise.version == 1
      Rails.root.join("../../experiments/rails-runtime/reference")
    elsif exercise.slug == "merge-intervals" && exercise.version == 2
      Rails.root.join("../../curriculum/ruby/merge-intervals/reference")
    elsif find(exercise.slug, exercise.version)
      Rails.root.join("../../curriculum/rails", exercise.slug, "reference")
    end
    return unless root
    Dir.glob(root.join("**/*.rb")).sort.to_h { |path| [Pathname.new(path).relative_path_from(root).to_s, File.read(path)] }
  end

  def self.review(exercise)
    entry = find(exercise.slug, exercise.version)
    return unless entry
    JSON.parse(File.read(Rails.root.join("../../curriculum/rails", entry.fetch("slug"), "review.json")))
  end
end
