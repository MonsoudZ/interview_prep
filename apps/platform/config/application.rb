require_relative "boot"
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "rails/test_unit/railtie"

module InterviewPlatform
  class Application < Rails::Application
    config.load_defaults 8.1
    config.eager_load = false
    config.public_file_server.enabled = true
    config.public_file_server.headers = { "Cache-Control" => "no-cache" }
    config.cache_store = :memory_store
    config.session_store :cookie_store, key: ENV.fetch("INTERVIEW_COOKIE_NAME", "_interview_platform"), httponly: true,
      same_site: :lax, secure: ENV["RAILS_ENV"] == "production", expire_after: 2_592_000
    config.filter_parameters += [:story, :sections, :password, :password_confirmation, :token, :lease_token, :signature, :files, :report, :input, :revision_context, :goal, :answer, :answers, :current_draft, :review_entries, :reflection]
    config.secret_key_base = if ENV["RAILS_ENV"] == "production"
      ENV.fetch("SECRET_KEY_BASE")
    else
      ENV.fetch("SECRET_KEY_BASE") { "development-only-never-deploy-" * 4 }
    end
    config.action_dispatch.default_headers.merge!({
      "Content-Security-Policy" => "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
      "Referrer-Policy" => "same-origin"
    })
  end
end
