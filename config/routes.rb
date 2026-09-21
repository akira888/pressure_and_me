Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  scope "/u/:uuid" do
    get "/", to: "condition_logs#new", as: :user_home
    post "/condition_logs", to: "condition_logs#create", as: :user_condition_logs
    get "/daily_log", to: "daily_logs#show", as: :user_daily_log
    put "/daily_log", to: "daily_logs#update"
    get "/analysis", to: "analyses#show", as: :user_analysis
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
