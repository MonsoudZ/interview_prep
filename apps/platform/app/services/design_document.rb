# Versioned, bounded diagram data. No raw SVG/HTML or external resources are accepted.
class DesignDocument
  NOTES = %w[requirements.md capacity.md api-data.md reliability.md tradeoffs.md notes.md].freeze
  FILES = (NOTES + ["diagram.json"]).freeze
  KINDS = %w[client service database queue cache external].freeze

  def self.validate!(text)
    invalid! unless text.is_a?(String) && text.bytesize <= 524_288
    document = JSON.parse(text)
    invalid! unless document.is_a?(Hash) && document.keys.sort == %w[edges nodes version] && document["version"] == 1
    nodes, edges = document.values_at("nodes", "edges")
    invalid! unless nodes.is_a?(Array) && edges.is_a?(Array) && nodes.length <= 50 && edges.length <= 100
    nodes.each do |node|
      invalid! unless node.is_a?(Hash) && node.keys.sort == %w[detail id kind label x y] && id?(node["id"]) && KINDS.include?(node["kind"])
      invalid! unless string?(node["label"], 80) && node["label"].strip.present? && string?(node["detail"], 1000)
      invalid! unless %w[x y].all? { |key| node[key].is_a?(Numeric) && node[key].finite? && node[key].between?(0, 4000) }
    end
    ids = nodes.map { |node| node.fetch("id") }
    invalid! unless ids.uniq.length == ids.length
    edges.each do |edge|
      invalid! unless edge.is_a?(Hash) && edge.keys.sort == %w[from id label to] && id?(edge["id"]) && string?(edge["label"], 120)
      invalid! unless ids.include?(edge["from"]) && ids.include?(edge["to"]) && edge["from"] != edge["to"]
    end
    invalid! unless edges.map { |edge| edge.fetch("id") }.uniq.length == edges.length
    invalid! unless (edges.map { |edge| edge.fetch("id") } & ids).empty?
    document
  rescue JSON::ParserError, TypeError
    invalid!
  end

  def self.id?(value) = value.is_a?(String) && value.match?(/\A[A-Za-z0-9_-]{1,64}\z/)
  def self.string?(value, length) = value.is_a?(String) && value.length <= length
  def self.invalid! = raise(Workspace::Invalid, "Invalid diagram: use the published version, component types, limits, and existing connection endpoints")
end
