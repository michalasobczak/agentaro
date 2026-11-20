Rails.application.routes.draw do
  root "home#show"

  # Spec 007: calendar of tasks
  get "calendar" => "calendar#show", as: :calendar
  get "calendar/stamp" => "calendar#stamp", as: :calendar_stamp # auto refresh
  resources :tasks, only: %i[new create show edit update destroy] do
    resources :runs, only: :create, controller: "task_runs" # spec 010: Run now
    member do
      get :stamp # auto refresh
      patch :move
      post :copy
      post :duplicate
    end
  end

  resources :agents # spec 009
  # Spec 011: chat with the director, the work list, the team
  resource :director, only: :show do
    get :stamp
  end
  resources :chat_messages, only: %i[index create], path: "director/messages"
  resources :work_items, only: %i[index show], path: "list" do
    member do
      post :retry
      post :done # spec 013, Q10
      post :cancel
    end
  end
  # Spec 013: projects with a kanban board of their epics
  resources :projects do
    member do
      patch :archive
      patch :activate
      patch :order
    end
  end
  resource :team, only: :show
  resources :team_roles, only: %i[create update destroy], path: "team/roles"
  resources :task_runs, only: :show, path: "runs" # spec 010
  resources :executors, only: :index # spec 008 (read-only for everyone, Q4)

  # Spec 002: sign-in, TOTP, password-change links
  resource :session, only: %i[new create destroy]
  resource :two_factor, only: %i[new create]
  resource :two_factor_enrollment, only: %i[new create]
  resource :password_reset, only: %i[show update] # token as a parameter, never in the path

  namespace :account do
    resources :sessions, only: %i[index destroy] do
      delete :others, on: :collection
    end
    resource :password, only: %i[edit update]
  end

  namespace :admin do
    root "users#index"
    resources :users, only: %i[index new create show update] do
      member do
        post :reset_totp
        post :revoke_sessions
      end
      resources :password_links, only: :create
    end
    resources :audit_events, only: :index   # spec 003
    resources :data_changes, only: :index   # spec 004
    resources :executors, only: %i[new create edit update destroy] do # spec 008
      post :check, on: :member
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
