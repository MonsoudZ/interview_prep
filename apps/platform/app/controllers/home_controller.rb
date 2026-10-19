class HomeController < ActionController::Base
  def index
    nonce = SecureRandom.base64(24)
    policy = Rails.application.config.action_dispatch.default_headers.fetch("Content-Security-Policy")
    response.headers["Content-Security-Policy"] = policy.sub("style-src 'self'", "style-src 'self' 'nonce-#{nonce}'")
    response.headers["Cache-Control"] = "no-store"
    shell = Rails.root.join("app/views/home/shell.html").read.sub("__STYLE_NONCE__", nonce)
    render html: shell.html_safe, layout: false
  end
end
