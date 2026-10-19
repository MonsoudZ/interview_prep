Rails.application.configure do
  config.eager_load = true
  config.force_ssl = true
  config.hosts = ENV.fetch("APP_HOSTS").split(",")
  # A shared auth rate-limit cache is a deployment gate; this local foundation is not deployment-ready.
end
