# CLAUDE.md

## Project Overview

Rails 8 + SolRengine dApp for on-chain community voting. A single curated poll
("Which dApp should we showcase next on solrengine.org?") backed by the
Solana Bootcamp 2026 voting Anchor program on devnet.

The distinguishing feature: the Rails DB stores **only users**. Polls,
candidates, and votes all live on-chain. Rails is a signing helper + view
layer; Solana is the database.

## Deployed program (devnet)

- Program ID: `2F1Z4eTmFqbjAnNWaDXXScoBYLMFn1gTasVy2mfPTeJx`
- Anchor program source: [solrengine/voting-anchor](https://github.com/solrengine/voting-anchor)
- Instructions: `initialize_poll`, `initialize_candidate`, `vote`
- IDL: `config/idl/voting.json` (mirror of `target/idl/voting.json` from the
  Anchor build in solrengine/voting-anchor)

## Key commands

- `bin/dev` — start all processes (web, js, css)
- `yarn build` / `yarn build:css` — one-shot JS / Tailwind build (use when
  running bare `rails server` instead of `bin/dev`)
- `bin/rails db:prepare` — set up all databases
- `bin/rails voting:init_poll` — initialize the pinned poll on-chain
- `bin/rails voting:init_candidates` — initialize each candidate PDA on-chain
  (idempotent per candidate)
- `bin/rails voting:verify` — assert `config/candidates.yml` still matches
  on-chain state; exits 1 on drift. Run before shipping any edit to the YAML.
- `bin/kamal deploy` — ship to production (see `DEPLOY.md`)

## Environment variables

- `SOLANA_NETWORK` — devnet (default) / testnet / mainnet
- `APP_DOMAIN` — SIWS domain + DNS rebinding host + mailer host
- `SOLANA_KEYPAIR_FILE` — path to a Solana CLI json-array keypair; used
  **only** by the `voting:*` rake tasks to sign poll + candidate
  initialization. Not needed for runtime voting (end-user wallets sign those).
- `SOLANA_RPC_URL` / `SOLANA_WS_URL` — optional mainnet RPC override

## Architecture

### Data model

- **On-chain (source of truth)**
  - `PollAccount` PDA — seeded by `["poll", poll_id_le]`. Holds poll name,
    description, start_time, end_time, option_index.
  - `CandidateAccount` PDA — seeded by `[poll_id_le, candidate_name]`. Holds
    candidate name + vote count (u64).
- **Rails DB (SQLite)**
  - `users` — wallet_address (Solana pubkey) + SIWS nonce. That's all.
- **YAML**
  - `config/candidates.yml` — presentation metadata (names, descriptions,
    URLs) plus the current poll id, start, end. Source of truth for what the
    UI renders.

### Request flow: GET /poll

1. `PollsController#show` → `load_poll_data`
2. For each PDA (poll + candidates): `Pda.find_program_address` to derive the
   address, `getAccountInfo` RPC to fetch bytes, Borsh decode via
   `Voting::PollAccount` / `Voting::CandidateAccount`
3. Merge with `Voting::CandidateConfig` (YAML) for names/URLs/blurbs
4. Compute voting_state: `:open` / `:not_started` / `:ended` / `:not_initialized`
5. Render `polls/show`

### Request flow: POST /poll/prepare_vote

1. `candidate` param from client (name), `signer` derived from
   `current_user.wallet_address` (SIWS-verified, never trusted from client)
2. Build `Voting::VoteInstruction.new(...)` — `solrengine-programs` derives
   both PDAs from the instruction's declarative seed specs
3. Fetch fresh blockhash via `Solrengine::Rpc.client.get_latest_blockhash`
4. Return JSON: `{ program_id, accounts, instruction_data (base64),
   blockhash, last_valid_block_height }`
5. Browser signs via `@solrengine/wallet-utils` → devnet RPC → program
   increments `candidate_votes`

## Key files

- `app/models/voting.rb` — `Voting::PROGRAM_ID` constant (override via
  `VOTING_PROGRAM_ID` env var)
- `app/models/voting/poll_account.rb` — Borsh-decoded PollAccount + `#open?`,
  `#ended?`, `#voting_state`, `#starts_at`, `#ends_at`
- `app/models/voting/candidate_account.rb` — Borsh-decoded CandidateAccount
- `app/models/voting/candidate_config.rb` — YAML loader (Poll + Candidate structs)
- `app/models/voting/poll_snapshot.rb` — value object that loads the current
  poll + candidates from chain per request and merges with YAML
- `app/models/voting/ballot_candidate.rb` — view-friendly candidate value object
- `app/models/voting/vote_instruction.rb` — Borsh-encoded vote ix with
  `#to_wire_payload(blockhash:)`
- `app/models/voting/initialize_poll_instruction.rb` — one-shot
- `app/models/voting/initialize_candidate_instruction.rb` — one-shot
- `app/controllers/polls_controller.rb` — `show` (renders HTML + JSON)
- `app/controllers/polls/votes_controller.rb` — `create` (prepare unsigned
  vote ix)
- `app/controllers/pages_controller.rb` — public landing (no auth)
- `app/javascript/controllers/voting_controller.js` — Stimulus; uses
  `@solrengine/wallet-utils` helpers (`findWalletByAddress`,
  `buildProgramInstruction`, `compileTransactionMessage`, `toWireBytes`,
  `signAndSend`)
- `lib/voting_keypair.rb` — json-array keypair loader (rake tasks only)
- `lib/tasks/voting.rake` — `voting:init_poll`, `voting:init_candidates`,
  `voting:verify`
- `config/candidates.yml` — poll + candidate definitions

## Conventions

- **Don't persist votes in Rails.** The chain is the source of truth.
  Computing counts happens per-request via `getAccountInfo`.
- **YAML vs. chain truth.** After `voting:init_*` has run, `config/candidates.yml`
  must match the on-chain `PollAccount` / `CandidateAccount` data verbatim
  (name, description, start/end, candidate names). Candidate name is the PDA
  seed — renaming in YAML silently breaks reads. Run `bin/rails voting:verify`
  before shipping any YAML edit; CI should run it too.
- **Don't trust the signer from the client.** Rails always uses
  `current_user.wallet_address`, verified during SIWS, for the `signer`
  account in instructions.
- **Always use `@solrengine/wallet-utils` helpers** for wallet discovery,
  instruction building, and signing. `findWalletByAddress` in particular
  solves the Backpack-auto-connect shadowing problem. Don't hand-roll with
  `@wallet-standard/app` primitives.
- **Never commit:** `config/master.key`, `.env` files, `config/deploy.yml`,
  `.kamal/secrets`.
- **Stimulus, never inline scripts.**
- **Leading-underscore arg names in IDL** — `solrengine-programs` v0.2.0
  strips these. If you need to regenerate from a new IDL, be aware the
  generator raises when a seed path has no matching arg after stripping.

## SolRengine packages

Ruby gems (all from RubyGems unless noted):
- `solrengine-auth` — SIWS authentication
- `solrengine-rpc` — JSON-RPC client singleton
- `solrengine-programs` — Anchor IDL parsing, Borsh, PDA derivation, code
  generator. **Currently referenced via local path** at
  `../solrengine-programs` on branch `feat/pda-from-idl` (v0.2.0 unreleased).
  Switch to the RubyGems version once v0.2.0 ships.
- `solrengine-ui` — ViewComponent UI library
- `solrengine-tokens` — SPL token metadata via Jupiter API

NPM:
- `@solrengine/wallet-utils` — WalletController, SendTransactionController,
  findWalletByAddress, buildProgramInstruction, etc.
- `@solrengine/ui` — Stimulus controllers for gem components
