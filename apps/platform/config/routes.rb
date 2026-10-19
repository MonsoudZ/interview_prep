Rails.application.routes.draw do
  root to: "home#index"
  get "/api/bootstrap", to: "auth#bootstrap"
  post "/api/register", to: "auth#register"
  post "/api/login", to: "auth#login"
  delete "/api/logout", to: "auth#logout"
  get "/api/exercises", to: "exercises#index"
  get "/api/progress", to: "progress#show"
  resources :mock_interviews, path: "/api/mock_interviews", only: [:index, :create, :show, :update] do
    member do
      post :archive
      post :restore
    end
  end
  resources :interview_sessions, path: "/api/sessions", controller: "interview_sessions", only: [:index, :create, :show] do
    member do
      post :archive
      post :restore
      put :snapshot
      post :prepare
      post :start
      post :submit
      post :execute
      get :practice
      get :timeline
      post :hint
      get :review, to: "session_reviews#show"
      get :automated_review, to: "automated_reviews#show"
      post :automated_review, to: "automated_reviews#create"
      get :reference, to: "session_reviews#reference"
      put :review, to: "session_reviews#update"
      get :rework, to: "reworks#show"
      post :rework, to: "reworks#create"
      get :rework_comparison, to: "reworks#comparison"
      get :followups, to: "followups#index"
      post :followups, to: "followups#create"
    end
  end
  get "/api/followups/:id", to: "followups#show"
  patch "/api/followups/:id", to: "followups#update"
  post "/internal/reviews/heartbeat", to: "review_gateway#heartbeat"
  post "/internal/reviews/lease", to: "review_gateway#lease"
  post "/internal/reviews/:id/result", to: "review_gateway#result"
  post "/internal/workers/heartbeat", to: "worker_gateway#heartbeat"
  post "/internal/workers/lease", to: "worker_gateway#lease"
  post "/internal/executions/:id/result", to: "worker_gateway#result"
end
