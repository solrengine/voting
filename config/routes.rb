Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # SIWS authentication — bundled controller from solrengine-auth v0.2.0.
  # Produces /auth/login, /auth/nonce, /auth/verify, /auth/logout.
  mount Solrengine::Auth::Engine => "/auth", as: :solrengine_auth

  # Voting dApp
  resource :poll, only: :show do
    resource :vote, only: :create, module: :polls, as: :prepare_vote
    get "confirm/:signature",
      to: "polls/votes#show",
      as: :confirm_vote,
      constraints: { signature: /[A-Za-z0-9]+/ }
  end

  root "pages#landing"
end
