# Trusted, published identities resolve local curriculum files; never request paths.
# Manifests, rubrics and references are immutable published files, so they are read once
# per process and deep-frozen; callers must copy before changing anything.
# Despite the name, this covers every manifest-published exercise; manifests carry a
# "track" (rails when absent) that selects the curriculum directory.
class RailsCurriculum
  def self.entries(track = nil)
    @entries ||= deep_freeze(Dir.glob(Rails.root.join("../../curriculum/{rails,ruby}/*/exercise.json")).sort.map { |path|
      JSON.parse(File.read(path)).tap { |entry| entry["track"] ||= "rails" }
    })
    track ? @entries.select { |entry| entry.fetch("track") == track } : @entries
  end

  def self.find(slug, version)
    entries.find { |entry| entry.fetch("slug") == slug && entry.fetch("version") == version }
  end

  def self.initial_path(exercise)
    find(exercise.slug, exercise.version)&.fetch("entry_file", nil) || {
      "tenant-projects" => "app/controllers/projects_controller.rb",
      "idempotent-checkout" => "app/controllers/orders_controller.rb",
      "delivery-retries" => "app/jobs/delivery_job.rb",
      "activity-feed" => "app/controllers/feed_controller.rb"
    }[exercise.slug]
  end

  ORDER = %w[repository-events tenant-projects idempotent-checkout delivery-retries activity-feed support-escalations invoice-amendments safe-backfill].freeze

  def self.reference(exercise)
    root = if exercise.slug == "repository-events" && exercise.version == 1
      Rails.root.join("../../experiments/rails-runtime/reference")
    elsif exercise.slug == "merge-intervals" && exercise.version == 2
      Rails.root.join("../../curriculum/ruby/merge-intervals/reference")
    elsif (entry = find(exercise.slug, exercise.version))
      Rails.root.join("../../curriculum", entry.fetch("track"), exercise.slug, "reference")
    end
    return unless root
    cache(:references, root.to_s) do
      Dir.glob(root.join("**/*.rb")).sort.to_h { |path| [Pathname.new(path).relative_path_from(root).to_s, File.read(path)] }
    end
  end

  def self.review(exercise)
    entry = find(exercise.slug, exercise.version)
    return unless entry
    cache(:reviews, entry.fetch("slug")) { JSON.parse(File.read(Rails.root.join("../../curriculum", entry.fetch("track"), entry.fetch("slug"), "review.json"))) }
  end

  def self.cache(store, key)
    (@caches ||= {})[store] ||= {}
    @caches[store].fetch(key) { @caches[store][key] = deep_freeze(yield) }
  end

  def self.deep_freeze(value)
    case value
    when Hash then value.each_value { |item| deep_freeze(item) }
    when Array then value.each { |item| deep_freeze(item) }
    end
    value.freeze
  end
end
