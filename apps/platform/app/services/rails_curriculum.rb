# Trusted, published identities resolve local curriculum files; never request paths.
# Manifests, rubrics and references are immutable published files, so they are read once
# per process and deep-frozen; callers must copy before changing anything.
# Despite the name, this covers every manifest-published exercise; manifests carry a
# "track" (rails when absent) that selects the curriculum directory.
#
# Each slug directory publishes its current version. When published text changes, the
# superseded manifest, BRIEF.md, review.json and reference/ are archived unchanged under
# versions/<n>/ so sessions created on that version keep reading their own rubric and
# reference; only the current manifest is seeded, advertised, and listed by `entries`.
class RailsCurriculum
  def self.entries(track = nil)
    @entries ||= manifests(Dir.glob(curriculum.join("{rails,ruby}/*/exercise.json")))
    track ? @entries.select { |entry| entry.fetch("track") == track } : @entries
  end

  def self.archived
    @archived ||= manifests(Dir.glob(curriculum.join("{rails,ruby}/*/versions/*/exercise.json"))).each do |entry|
      path = directory(entry)
      unless path.join("exercise.json").file? && path.join("BRIEF.md").file? && path.join("review.json").file? && path.join("reference").directory?
        raise "Archived manifest #{entry.fetch('slug')} v#{entry.fetch('version')} must keep its exercise.json, BRIEF.md, review.json and reference/ under #{path}"
      end
    end
  end

  def self.find(slug, version)
    (entries + archived).find { |entry| entry.fetch("slug") == slug && entry.fetch("version") == version }
  end

  # The directory holding an entry's review.json and reference/.
  def self.directory(entry)
    base = curriculum.join(entry.fetch("track"), entry.fetch("slug"))
    entries.include?(entry) ? base : base.join("versions", entry.fetch("version").to_s)
  end

  def self.curriculum
    Rails.root.join("../../curriculum")
  end

  def self.manifests(paths)
    deep_freeze(paths.sort.map { |path|
      JSON.parse(File.read(path)).tap { |entry|
        entry["track"] ||= "rails"
        expected = path.include?("/versions/") ? File.basename(File.dirname(File.dirname(File.dirname(path)))) : File.basename(File.dirname(path))
        raise "Manifest #{path} publishes slug #{entry['slug'].inspect} from directory #{expected}" unless entry["slug"] == expected
        if path.include?("/versions/") && entry["version"].to_s != File.basename(File.dirname(path))
          raise "Archived manifest #{path} must sit under versions/#{entry['version']}"
        end
      }
    })
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
      directory(entry).join("reference")
    end
    return unless root
    cache(:references, root.to_s) do
      Dir.glob(root.join("**/*.rb")).sort.to_h { |path| [Pathname.new(path).relative_path_from(root).to_s, File.read(path)] }
    end
  end

  def self.review(exercise)
    entry = find(exercise.slug, exercise.version)
    return unless entry
    cache(:reviews, "#{entry.fetch('slug')}-v#{entry.fetch('version')}") { JSON.parse(File.read(directory(entry).join("review.json"))) }
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
