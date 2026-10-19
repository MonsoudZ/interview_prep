# Build from repository root. Supply an approved Linux Ruby image pinned by digest.
# This image build requires Linux/Docker validation before use.
ARG RUBY_BASE
FROM ${RUBY_BASE}
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libsqlite3-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/exercise
COPY services/execution_worker/image/dependencies/Gemfile ./Gemfile
COPY services/execution_worker/image/dependencies/Gemfile.lock ./Gemfile.lock
# Compile native gems for the selected Linux image, without changing dependency versions.
ENV BUNDLE_FORCE_RUBY_PLATFORM=true BUNDLE_FROZEN=true
RUN bundle install
COPY experiments/rails-runtime/template/app ./app
COPY experiments/rails-runtime/template/config ./config
COPY experiments/rails-runtime/template/db ./db
COPY experiments/rails-runtime/template/bin ./bin
COPY experiments/rails-runtime/template/test ./test
COPY experiments/rails-runtime/template/BRIEF.md ./BRIEF.md
COPY curriculum/rails/tenant-projects/starter /opt/curriculum/tenant-projects/starter
COPY curriculum/rails/idempotent-checkout/starter /opt/curriculum/idempotent-checkout/starter
COPY curriculum/rails/delivery-retries/starter /opt/curriculum/delivery-retries/starter
COPY curriculum/rails/activity-feed/starter /opt/curriculum/activity-feed/starter
COPY curriculum/rails/support-escalations/starter /opt/curriculum/support-escalations/starter
COPY curriculum/rails/invoice-amendments/starter /opt/curriculum/invoice-amendments/starter
COPY curriculum/rails/safe-backfill/starter /opt/curriculum/safe-backfill/starter
COPY curriculum/ruby/merge-intervals/starter /opt/ruby/merge-intervals/starter
COPY curriculum/ruby/merge-intervals/hidden_test.rb /opt/ruby/merge-intervals/hidden_test.rb
COPY services/execution_worker/image/ruby.rb /opt/runner/ruby.rb
COPY services/execution_worker/image/run.rb /opt/runner/run.rb
RUN chmod -R a-w /opt/exercise /opt/runner /opt/curriculum /opt/ruby && mkdir /workspace && chown 1000:1000 /workspace
LABEL interview.curriculum="rails-ruby-v2"
LABEL interview.exercise="rails.events.v1" interview.contract="1"
USER 1000:1000
WORKDIR /workspace
ENV RAILS_ENV=test
ENTRYPOINT ["ruby", "/opt/runner/run.rb"]
