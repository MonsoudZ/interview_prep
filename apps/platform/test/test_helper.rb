ENV["RAILS_ENV"] = "test"
ENV["ALLOW_REGISTRATION"] = "true"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  parallelize(workers: 1)
end
