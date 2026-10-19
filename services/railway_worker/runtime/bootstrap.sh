#!/bin/bash
set -euo pipefail
test "$(id -u)" = 0
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends ruby ruby-dev build-essential libsqlite3-dev libyaml-dev pkg-config util-linux iproute2 ca-certificates
ruby -e 'abort "Ruby >= 3.2 is required by this exercise" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2")'
gem install bundler -v 4.0.3 --no-document
export BUNDLE_PATH=/opt/bundle BUNDLE_APP_CONFIG=/opt/bundle-config BUNDLE_FROZEN=true BUNDLE_FORCE_RUBY_PLATFORM=true
mkdir -p /opt/bundle-config
cd /opt/exercise
bundle _4.0.3_ install --jobs 1 --retry 1
if ! id interview >/dev/null 2>&1; then
  useradd --system --uid 20000 --user-group --no-create-home --shell /usr/sbin/nologin interview
fi
test "$(id -u interview)" = 20000
install -d -o 20000 -g "$(id -g interview)" -m 0700 /workspace
chown -R root:root /opt/exercise /opt/runner /opt/bundle /opt/bundle-config
chmod -R a-w /opt/exercise /opt/runner /opt/bundle /opt/bundle-config
printf 'Runtime installed: '
ruby --version
bundle _4.0.3_ --version
