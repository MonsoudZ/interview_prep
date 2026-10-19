ENV["RAILS_ENV"] = "test"
require "fileutils"
FileUtils.mkdir_p(File.expand_path("../storage", __dir__))
require_relative "../config/environment"
ActiveRecord::Schema.verbose = false
load Rails.root.join("db/schema.rb")
puts "READY: Rails #{Rails.version}; SQLite connection and schema verified"
