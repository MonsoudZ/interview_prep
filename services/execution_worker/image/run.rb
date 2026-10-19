# Trusted image entrypoint. Candidate code runs only after source has been staged.
require "json"
require "base64"
require "fileutils"
require "pathname"

MAX_INPUT = 2 * 1024 * 1024
input = STDIN.read(MAX_INPUT + 1)
abort "Input limit exceeded" if input.bytesize > MAX_INPUT
payload = JSON.parse(input)
files = payload.fetch("files")
abort "Invalid files" unless files.is_a?(Hash) && files.size.between?(1, 128)

scenario = nil
if (index = ARGV.index("--exercise"))
  scenario = ARGV[index + 1]
  abort "Unknown exercise" unless %w[tenant-projects idempotent-checkout delivery-retries activity-feed].include?(scenario)
end

Dir.chdir("/workspace") do
  FileUtils.cp_r(Dir.glob("/opt/exercise/*"), ".")
  FileUtils.chmod_R("u+w", Dir.glob("*"))
  FileUtils.cp_r(Dir.glob("/opt/curriculum/#{scenario}/starter/*"), ".") if scenario
  FileUtils.chmod_R("u+w", Dir.glob("*"))
  total = 0
  files.each do |name, encoded|
    safe = name.is_a?(String) && name.match?(/\A[A-Za-z0-9_.\/-]+\z/) &&
      !name.start_with?("/") && !name.split("/").any? { |part| [".", "..", ""].include?(part) } &&
      ((name.start_with?("app/") && name.end_with?(".rb")) || ["config/routes.rb", "db/schema.rb"].include?(name))
    abort "Invalid source path" unless safe
    content = Base64.strict_decode64(encoded)
    total += content.bytesize
    abort "Source limit exceeded" if total > 1024 * 1024
    FileUtils.mkdir_p(File.dirname(name))
    File.binwrite(name, content)
  end
  unless system("ruby", "bin/prepare.rb")
    warn "Exercise preparation failed"
    exit 70
  end
  exit 0 if ARGV.include?("--prepare")
  system("ruby", "-Itest", "test/integration/events_test.rb")
  status = $?
  exit(status.exitstatus || 128 + status.termsig)
end
