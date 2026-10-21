require_relative "../../../apps/platform/config/environment"
value = JSON.parse(File.read(ARGV.fetch(0)))
AutomatedReviewReport.check!(value.fetch("report"), value.fetch("packet"))
puts "Report schema, rubric identity, and source citations accepted."
