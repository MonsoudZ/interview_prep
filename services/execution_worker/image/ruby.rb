# Trusted Ruby exercise dispatcher. Candidate source is evaluated only inside the isolated worker.
require "json"
require "base64"
require "fileutils"
input = STDIN.read(2 * 1024 * 1024 + 1)
abort "Input limit exceeded" if input.bytesize > 2 * 1024 * 1024
files = JSON.parse(input).fetch("files")
abort "Only solution.rb is accepted" unless files.is_a?(Hash) && files.keys == ["solution.rb"]
source = Base64.strict_decode64(files.fetch("solution.rb"))
abort "Source limit exceeded" if source.bytesize > 1024 * 1024
Dir.chdir("/workspace") do
  FileUtils.cp_r(Dir.glob("/opt/ruby/merge-intervals/starter/*"), ".")
  FileUtils.chmod_R("u+w", Dir.glob("*"))
  File.binwrite("solution.rb", source)
  if ARGV.include?("--prepare")
    # Compile only: no require/eval of the implementation during readiness checks.
    RubyVM::InstructionSequence.compile(source, "solution.rb")
    puts "READY: Ruby syntax verified; implementation has not been executed"
    exit 0
  end
  require_relative "/workspace/test/visible_test"
  require_relative "/opt/ruby/merge-intervals/hidden_test"
end
