# frozen_string_literal: true

Rails.application.routes.draw do
  get "emails/new"
  get "emails/create"

  # Root and Home
  root "home#index"
  get "home/index"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up", to: "rails/health#show", as: :rails_health_check

  # Login

  get "/login", to: redirect("/auth/google_oauth2"), as: :login
  get "/auth/:provider/callback", to: "sessions#create"
  get "/auth/failure", to: redirect("/")
  get "/logout", to: "sessions#destroy", as: "logout"

  resources :sessions, only: [ :new, :create, :destroy ]
  resources :sessions, only: [ :new, :create, :destroy ]

  # Records
  get "all_records", to: "records#index"
  resources :records, only: [ :destroy ]
  post "records/destroy_unconfirmed", to: "records#destroy_unconfirmed", as: "destroy_unconfirmed_assignments"
  post "toggle_assignment", to: "records#toggle_assignment", as: :toggle_assignment
  post "revoke_assignment", to: "records#revoke_assignment", as: :revoke_assignment
  post "manual_confirm", to: "records#manual_confirm", as: :manual_confirm
  post "mass_confirm", to: "records#mass_confirm", as: :mass_confirm
  post "mass_toggle_assignment", to: "records#mass_toggle_assignment", as: :mass_toggle_assignment


  # TA Assignments

  get "ta_assignments/new"
  get "ta_assignments/create"
  get "download_csv", to: "ta_assignments#download_csv", as: :download_csv_ta_assignments
  get "recommendations/new"

  resources :ta_assignments, only: [ :index, :edit, :update, :destroy ]

  resources :emails, only: [ :new, :create ]
  # Applicants

  delete "wipe_applicants", to: "applicants#wipe_applicants"
  resources :applicants do
    collection do
      get :my_application
      get :search
      get :search_email
      get :search_uin
    end
  end
 
  post 'toggle_blacklist', to: 'applicants#toggle_blacklist', as: 'toggle_blacklist'

  resources :unassigned_applicantsapplicants do
    collection do
      get :search
      get :search_email
      get :search_uin
      get :search_course
    end
  end

  resources :courses, only: [ :index, :update, :destroy, :create ] do
    collection do
      post :import
      delete :clear
      get :search
      get :search_recs
    end
  end

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest


  resources :assignments, only: [ :index ] do
    collection do
      post :import_csv   # POST /assignments/import_csv
      post :assign_ta
      get :assign_ta
    end
  end

  # TA assignment
  post "ta_assignments/process_csvs", to: "ta_assignments#process_csvs", as: "process_csvs"
  get "ta_assignments/view_csv", to: "ta_assignments#view_csv", as: "view_csv"
  post "import_csv", to: "csv_imports#import", as: "import_csv"
  delete "delete_all_csvs", to: "ta_assignments#delete_all_csvs", as: "delete_all_csvs"

  get "ta_assignments/calibrate_unassigned_applicants", to: "ta_assignments#calibrate_unassigned_applicants", as: "calibrate_unassigned_applicants"
  # post "/ta_assignments/destroy_unconfirmed", to: "ta_assignments#destroy_unconfirmed", as: "destroy_unconfirmed_assignments"



  # TA reassignment
  post "ta_reassignments/process_csvs", to: "ta_reassignments#process_csvs", as: "reprocess_csvs"
  get "ta_reassignments/view_csv", to: "ta_reassignments#view_csv", as: "review_csv"
  get "ta_reassignments/new", to: "ta_reassignments#new", as: "ta_reassignments_new"


  # Recommendation system
  resources :recommendations, only: [ :new, :create, :index, :edit, :destroy, :update ] do
    collection do
      delete :clear
    end
  end

  get "recommendations/show", to: "recommendations#show", as: "recommendation_view"
  get "recommendations/mine", to: "recommendations#my_recommendations", as: "my_recommendations_view"

  get "courses/search", to: "courses#search"
  get "applicants/search", to: "applicants#search"

  get "unassigned_applicants/search", to: "unassigned_applicants#search"
  get "unassigned_applicants/search_uin", to: "unassigned_applicants#search_uin"
  get "unassigned_applicants/search_email", to: "unassigned_applicants#search_email"

  # blacklist
  resources :blacklists, only: [ :index, :create, :destroy ]

  # export
  get "export_courses", to: "courses#export", as: :export_courses

  # withdrawer
  resources :withdrawal_requests, only: [ :new, :create, :index, :show ] do
    collection do
      delete :clear
    end
  end

  # post 'toggle_assignment', to: 'withdrawal_requests#toggle_assignment', as: :toggle_assignment
  post "confirm_assignment", to: "withdrawal_requests#confirm_assignment", as: :confirm_assignment
  # post 'revoke_assignment', to: 'withdrawal_requests#revoke_assignment', as: :revoke_assignment
  # post 'mass_confirm', to: 'withdrawal_requests#mass_confirm', as: :mass_confirm
  # post 'mass_toggle_assignment', to: 'withdrawal_requests#mass_toggle_assignment', as: :mass_toggle_assignment

  resources :withdrawal_requests, only: [ :new, :create, :index, :show ] do
    collection do
      delete :clear
    end
  end

  get "ta_assignments#export_final_csv", to: "ta_assignments#export_final_csv", as: "export_final_csv"

  delete "wipe_users", to: "application#wipe_users"
  resources :advisors, only: [ :index, :new, :create, :destroy ] do
    collection do
      post :import_csv
    end
  end
  post "advisors/clear", to: "advisors#clear", as: "clear_advisor"

  # admin
  resources :admins, only: [ :new, :create ]
  get "admin/manage_data", to: "admin#manage_data", as: :admin_manage_data
  get "admins/export", to: "admins#export", as: "export_admins"
  post "import", to: "admins#import"
  post "admin/clear", to: "admins#clear", as: "clear_data"
end
