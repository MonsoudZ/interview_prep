require "test_helper"

class ReviewGuidanceTest < ActiveSupport::TestCase
  test "selects relevant sources and preserves public source types" do
    ruby = ReviewGuidance.for("ruby")
    assert_equal %w[google-interview-preparation google-code-review amazon-senior-interview ruby-hash-semantics], ruby.fetch("sources").map { |s| s.fetch("id") }
    design = ReviewGuidance.for("system_design")
    assert_includes design.fetch("sources").map { |s| s.fetch("company") }, "Apple"
    refute_includes design.fetch("sources").map { |s| s.fetch("id") }, "google-code-review"
    apple = design.fetch("sources").find { |s| s["company"] == "Apple" }
    assert_includes apple.fetch("kind"), "not interview scoring"
    assert_empty ReviewGuidance.for("behavioral").fetch("sources")
    assert_equal ruby, ReviewGuidance.for("ruby")
    refute_equal ruby.fetch("digest"), design.fetch("digest")
    assert_operator JSON.generate(ruby).bytesize, :<, 6000
  end

  test "returned copies and old provenance do not depend on later catalog changes" do
    saved = ReviewGuidance.for("ruby")
    expected = saved.deep_dup
    ReviewGuidance.for("ruby")["sources"].clear
    assert_equal expected, saved
    assert_nil ReviewGuidance.provenance(nil)
    provenance = ReviewGuidance.provenance(saved)
    assert_equal saved["digest"], provenance[:digest]
    refute provenance[:sources].first.key?("summary")
  end
end
