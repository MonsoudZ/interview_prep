Rails.application.routes.draw do
  post "/tickets/:id/escalate", to: "escalations#create"
end
