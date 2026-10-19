# Trusted prelude: fail closed before loading candidate files.
require "socket"
abort "RUNTIME_POLICY: non-root UID unavailable" unless Process.uid == 20000
abort "RUNTIME_POLICY: network namespace unavailable" unless Socket.getifaddrs.map(&:name).uniq == ["lo"]
status = File.read("/proc/self/status")
abort "RUNTIME_POLICY: privileges were not dropped" unless status.match?(/^CapEff:\s+0+$/) && status.match?(/^NoNewPrivs:\s+1$/)
abort "RUNTIME_POLICY: trusted runtime is writable" if File.writable?("/opt/runner/run.rb") || File.writable?("/opt/exercise/Gemfile")
abort "RUNTIME_POLICY: Docker socket is exposed" if File.exist?("/var/run/docker.sock")
begin
  connection = Socket.tcp("1.1.1.1", 443, connect_timeout: 1)
  connection.close
  abort "RUNTIME_POLICY: outbound TCP is reachable"
rescue SystemCallError, IOError
  # A newly created network namespace has no route and no configured loopback.
end
puts "[runtime] uid=20000; network=none; privileges=dropped; trusted_files=read_only"
