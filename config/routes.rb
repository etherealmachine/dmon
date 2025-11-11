Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: 'users/omniauth_callbacks'
  }, skip: [:registrations]

  # Login/logout routes
  get '/login', to: redirect('/users/auth/google_oauth2'), as: :login
  delete '/logout', to: 'sessions#destroy', as: :logout

  # Game routes
  resources :games, only: [:index, :new, :create, :show] do
    get :agent, on: :member
    post :agent, on: :member
    resources :game_notes, only: [:create, :update, :destroy] do
      post :call_action, on: :member
      post :clear_history, on: :member
      post :update_stat, on: :member
      post :delete_stat, on: :member
      post :delete_action, on: :member
      post :delete_history_item, on: :member
    end
    resources :pdfs, only: [:show, :create] do
      get :html, on: :member
      post :reparse, on: :member
      post :reclassify_images, on: :member
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "games#index"
end
