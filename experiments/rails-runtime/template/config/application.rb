require_relative "boot"
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "rails/test_unit/railtie"

module EventsExercise
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    config.eager_load = false
    config.secret_key_base = "local-trusted-experiment-only-" * 4
    config.hosts = ["www.example.com", "localhost"]
    config.active_support.deprecation = :stderr
  end
end
