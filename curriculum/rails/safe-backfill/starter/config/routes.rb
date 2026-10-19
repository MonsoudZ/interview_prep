Rails.application.routes.draw do
  get "/customers/:id", to: "customers#show"
end
