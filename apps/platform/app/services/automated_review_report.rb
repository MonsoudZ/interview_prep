# Source locations and execution identities are validated here, independently of the model.
# This cannot establish semantic truth: even a correctly cited model observation can be wrong.
class AutomatedReviewReport
  def self.check!(raw, packet)
    invalid! unless raw.is_a?(Hash) && JSON.generate(raw).bytesize <= 80000
    exact!(raw, %w[summary criteria findings strengths understanding_checks limitations])
    text!(raw["summary"], 1800)
    array!(raw["criteria"], 12)
    expected = packet.fetch("rubric").map { |criterion| criterion.fetch("id") }.sort
    invalid! unless raw["criteria"].map { |c| c.is_a?(Hash) && c["id"] }.sort_by(&:to_s) == expected
    result = Marshal.load(Marshal.dump(raw))
    result["criteria"].each do |entry|
      exact!(entry, %w[id rating reasoning evidence])
      invalid! unless ReviewWorkflow::RATINGS.include?(entry["rating"])
      text!(entry["reasoning"], 2000)
      evidence!(entry["evidence"], packet, required: entry["rating"] != "not_observed")
    end
    array!(result["findings"], 16)
    result["findings"].each do |finding|
      exact!(finding, %w[severity category title observation consequence recommendation confidence evidence execution_ids])
      invalid! unless %w[major minor].include?(finding["severity"]) && %w[source_concern design_concern execution_observation refinement].include?(finding["category"]) && %w[high medium low].include?(finding["confidence"])
      %w[title observation consequence recommendation].each { |key| text!(finding[key], key == "title" ? 150 : 1800) }
      evidence!(finding["evidence"], packet, required: true)
      array!(finding["execution_ids"], 3)
      available = packet.fetch("executions").map { |run| run.fetch("id") }
      invalid! unless finding["execution_ids"].all? { |id| id.is_a?(String) && available.include?(id) }
      invalid! if finding["category"] == "execution_observation" && finding["execution_ids"].empty?
    end
    array!(result["strengths"], 8)
    result["strengths"].each do |strength|
      exact!(strength, %w[statement evidence]); text!(strength["statement"], 1500)
      evidence!(strength["evidence"], packet, required: true)
    end
    %w[understanding_checks limitations].each do |key|
      array!(result[key], 8); result[key].each { |text| text!(text, 1000) }
    end
    result
  end

  def self.evidence!(items, packet, required:)
    array!(items, 4)
    invalid! if required && items.empty?
    items.each do |citation|
      exact!(citation, %w[path start_line end_line])
      source = packet.fetch("files")[citation["path"]]
      first, last = citation.values_at("start_line", "end_line")
      invalid! unless source.is_a?(String) && first.is_a?(Integer) && last.is_a?(Integer) && first >= 1 && last >= first && last <= source.lines.length && last - first < 20
      excerpt = source.lines[(first - 1)..(last - 1)].join
      invalid! if excerpt.bytesize > 6000
      citation["excerpt"] = excerpt
    end
  end
  def self.exact!(item, keys) = (invalid! unless item.is_a?(Hash) && item.keys.sort == keys.sort)
  def self.array!(item, maximum) = (invalid! unless item.is_a?(Array) && item.length <= maximum)
  def self.text!(item, maximum) = (invalid! unless item.is_a?(String) && item.strip.present? && item.length <= maximum)
  def self.invalid! = raise(Workspace::Invalid, "Review output did not meet the evidence contract")
end
