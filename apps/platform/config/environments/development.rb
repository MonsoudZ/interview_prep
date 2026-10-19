Rails.application.configure do
  config.hosts = ["localhost", "127.0.0.1", "[::1]"]
  config.action_dispatch.show_exceptions = :none
end
