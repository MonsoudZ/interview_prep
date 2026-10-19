# Trusted Ruby exercise dispatcher. Candidate source is evaluated only inside the isolated worker.
require "json"
require "base64"
require "fileutils"
RUBY_ROOT = "/opt/ruby"
WORKSPACE = "/workspace"
EXERCISES = %w[merge-intervals lru-cache rate-limiter build-order].freeze
slug = "merge-intervals"
if (index = ARGV.index("--exercise"))
  slug = ARGV[index + 1]
  abort "Unknown exercise" unless EXERCISES.include?(slug)
end
prepare = ARGV.include?("--prepare")
ARGV.clear # Minitest parses ARGV when the test files load; dispatcher flags are not test options.
input = STDIN.read(2 * 1024 * 1024 + 1)
abort "Input limit exceeded" if input.bytesize > 2 * 1024 * 1024
files = JSON.parse(input).fetch("files")
abort "Only solution.rb is accepted" unless files.is_a?(Hash) && files.keys == ["solution.rb"]
source = Base64.strict_decode64(files.fetch("solution.rb"))
abort "Source limit exceeded" if source.bytesize > 1024 * 1024
Dir.chdir(WORKSPACE) do
  FileUtils.cp_r(Dir.glob("#{RUBY_ROOT}/#{slug}/starter/*"), ".")
  FileUtils.chmod_R("u+w", Dir.glob("*"))
  File.binwrite("solution.rb", source)
  if prepare
    # Compile only: no require/eval of the implementation during readiness checks.
    RubyVM::InstructionSequence.compile(source, "solution.rb")
    puts "READY: Ruby syntax verified; implementation has not been executed"
    exit 0
  end
  require_relative "#{WORKSPACE}/test/visible_test"
  require_relative "#{RUBY_ROOT}/#{slug}/hidden_test"
end
