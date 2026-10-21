# Curated public-source summaries are context, never additional assessment requirements.
# Copy the selected material into the immutable review packet before inference.
class ReviewGuidance
  CATALOG = Rails.root.join("../../curriculum/reviewer_guidance/sources.json").freeze

  def self.for(track)
    catalog = JSON.parse(File.read(CATALOG))
    sources = catalog.fetch("sources").select { |source| source.fetch("tracks").include?(track) }
    selected = { "version" => catalog.fetch("version"), "sources" => sources }
    selected.merge("digest" => "sha256:#{Digest::SHA256.hexdigest(JSON.generate(selected))}")
  end

  def self.provenance(guidance)
    return nil unless guidance.is_a?(Hash)
    { version: guidance["version"], digest: guidance["digest"],
      sources: guidance.fetch("sources", []).map { |source| source.slice("id", "company", "title", "url", "kind", "checked_on") } }
  end
end
