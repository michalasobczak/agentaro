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
  resources :model_checks, only: :create, path: "models/check" # spec 022: Check model
  # Spec 011: chat with the director, the work list, the team
  resource :director, only: :show do
    get :stamp
    post :new_conversation # spec 015
    post :verify # spec 019: invite the verifier, or send it away
    patch :speech_speed
    get :archive
  end
  # Spec 017: voice for the director chat
  post "director/voice/transcribe", to: "chat_messages#transcribe", as: :voice_transcribe, defaults: { format: :json }
  post "director/voice/speak", to: "voices#speak", as: :voice_speak
  get "director/voice/status", to: "voices#status", as: :voice_status
  patch "director/language", to: "voices#language", as: :chat_language
  resources :chat_messages, only: %i[index create], path: "director/messages"
  resources :work_items, only: :show, path: "epics" do # owner fix after spec 013: no list page; epics live on their space boards
    member do
      post :retry
      post :done # spec 013, Q10
      post :cancel
    end
  end
  # Spec 013: spaces with a kanban board of their epics
  resources :spaces do
    get :folders, on: :collection # owner fix after spec 018: folder suggestions while typing
    member do
      patch :archive
      patch :activate
      patch :order
    end
  end
  resource :team, only: :show do
    get :status # spec 023: busy or free
  end
  resources :team_roles, only: %i[create update destroy], path: "team/roles"
  resources :task_runs, only: :show, path: "runs" do # spec 010
    get :stamp, on: :member # owner fix: the run page refreshes itself without <meta refresh> (spec 020)
  end
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
      post :refresh_models, on: :member # spec 022, G3
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
