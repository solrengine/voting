# Voting

On-chain community voting dApp for picking the next dApp to showcase on [solrengine.org](https://solrengine.org). Built with **Rails 8** and the [SolRengine](https://solrengine.org) framework. Voting is signed by the user's wallet; counts live on Solana devnet.

Live at [voting.solrengine.org](https://voting.solrengine.org).

Live poll (single curated poll): **"Which dApp should we showcase next on solrengine.org?"**

- **Anchor program source:** [solrengine/voting-anchor](https://github.com/solrengine/voting-anchor)
- **Deployed program (devnet):** [`2F1Z4eTmFqbjAnNWaDXXScoBYLMFn1gTasVy2mfPTeJx`](https://solscan.io/account/2F1Z4eTmFqbjAnNWaDXXScoBYLMFn1gTasVy2mfPTeJx?cluster=devnet)

## How it works

- **Rails** is a view layer + signing helper. The SQLite DB stores only users (wallet address + SIWS nonce).
- **Solana** is the database. `PollAccount` and `CandidateAccount` PDAs hold the poll metadata and vote counts.
- **`config/candidates.yml`** holds presentation metadata (names, descriptions, URLs) that's too expensive to put on-chain.
- **Vote flow:** browser → `POST /poll/vote` → Rails builds a Borsh-encoded instruction and derives PDAs via `solrengine-programs` → wallet signs via `@solrengine/wallet-utils` → devnet RPC → validator increments `candidate_votes` on the candidate's PDA.

## Quick start (local dev)

```sh
bundle install
yarn install
bin/rails db:prepare
bin/dev                # runs web + js watcher + css watcher
```

Open <http://localhost:3000>, connect a wallet, and vote.

## Running your own poll

The voting program is generic — one program can host many polls. Each poll is identified by a `poll_id` (u64). To run a new poll on top of the existing deployed program:

### 1. Edit `config/candidates.yml`

```yaml
poll:
  id: 3                  # bump the id to start a fresh poll
  name: "Your poll question"
  description: "One-line explanation"
  start_time: 1776297600 # Unix timestamp (seconds)
  end_time:   1807920000

candidates:
  - name: "OptionOne"
    description: "Short blurb"
    url: "https://..."
  - name: "OptionTwo"
    description: "..."
    url: "https://..."
```

**Constraints:**
- `poll.id` must be unique per poll (the program refuses to re-initialize an existing PollAccount).
- Candidate `name` is part of the on-chain PDA seed, so names must be unique per poll and reasonably short (under 32 bytes). Renaming a candidate after initialization creates a *new* on-chain account — the old one stays put with any votes it has.
- `start_time` / `end_time` are Unix timestamps in UTC. The voting program enforces the window on-chain.

### 2. Initialize on-chain

Point `SOLANA_KEYPAIR_FILE` at a funded Solana CLI keypair (json array format). The account needs ~0.1 SOL on devnet to cover rent for the PollAccount + each CandidateAccount:

```sh
export SOLANA_KEYPAIR_FILE=~/.config/solana/id.json
bin/rails voting:init_poll
sleep 5                        # wait for confirmation before candidates
bin/rails voting:init_candidates
```

Each task prints a Solscan link to the transaction. `voting:init_candidates` is idempotent per candidate — if one is already initialized, it skips and continues with the rest.

### 3. Verify

```sh
bin/rails runner 'pp Voting::CandidateConfig.candidates.map(&:name)'
```

Visit `/poll` — you should see the new question, candidates, and live vote counts (all zero).

## Running a second, separate voting instance

The `voting` Anchor program is deployed once; the dApp is what gets forked. To run a completely independent poll (different branding, different candidates, different subdomain):

1. Clone this repo to a new directory, point it at a new GitHub repo.
2. Edit `config/candidates.yml` with your poll (use a `poll.id` that doesn't collide with existing polls on the shared program — check Solscan).
3. Deploy with Kamal to your own domain (see [DEPLOY.md](DEPLOY.md)).
4. Run the rake tasks against your funded keypair.

Because the program lives on-chain and is stateless per instruction, multiple dApp instances can share it without interfering — they each write to a different `poll_id` namespace.

## Deploying a *new* voting program

You generally don't need to. The existing devnet deployment is open for anyone's `poll_id`. But if you want full control (mainnet, anti-sybil features, custom logic), redeploy the Anchor program from [solrengine/voting-anchor](https://github.com/solrengine/voting-anchor):

1. `git clone https://github.com/solrengine/voting-anchor.git && cd voting-anchor`
2. `anchor build && anchor deploy --provider.cluster <devnet|mainnet>`
3. Copy `target/idl/voting.json` to this app's `config/idl/voting.json`
4. Set `VOTING_PROGRAM_ID` env var (or update `app/models/voting.rb`) to the new program address
5. Run the rake tasks above to initialize the poll + candidates against your new program

## Production deploy

See [DEPLOY.md](DEPLOY.md) for Kamal + Let's Encrypt + SIWS domain config.

## Automated / agent usage

Every user-visible action has a JSON equivalent. An agent with its own
Solana keypair can drive the full flow without a browser wallet.

**1. Fetch a nonce.**

```sh
curl -s -c cookies.txt -H 'Accept: application/json' \
  "https://<host>/auth/nonce?wallet_address=<base58_pubkey>"
# => { "message": "<domain> wants you to sign in with...\nNonce: <hex>", "nonce": "<hex>" }
```

**2. Sign the `message` bytes with the wallet's secret key (ed25519).**
Send the signature back base64-encoded:

```sh
curl -s -b cookies.txt -c cookies.txt -H 'Accept: application/json' \
  -H 'X-CSRF-Token: <from /poll HTML meta or previous session>' \
  -H 'Content-Type: application/json' \
  -d '{"wallet_address":"...","message":"...","signature":"<base64>"}' \
  "https://<host>/auth/verify"
```

**3. Read poll state.** `/poll.json` returns `{ poll, state, candidates, program_id }`:

```sh
curl -s -b cookies.txt -H 'Accept: application/json' "https://<host>/poll.json"
```

**4. Prepare an unsigned vote.** Returns instruction bytes + a fresh blockhash:

```sh
curl -s -b cookies.txt -H 'Accept: application/json' \
  -H 'X-CSRF-Token: ...' -H 'Content-Type: application/json' \
  -d '{"candidate":"PiggyBank"}' \
  "https://<host>/poll/vote"
# => { program_id, accounts, instruction_data (b64), blockhash, last_valid_block_height }
```

**5. Compile + sign + submit.** The agent compiles a legacy Solana tx from the
returned fields, signs with its keypair, and submits via `sendTransaction`.

**Error codes.** 422/409 responses always include a machine-readable `code`:
`unknown_candidate`, `candidate_too_long`, `not_started`, `ended`,
`not_initialized`, `invalid_instruction`.

**Rake tasks in a container.** `voting:init_*` and `voting:verify` accept
either `SOLANA_KEYPAIR_FILE=<path>` or `SOLANA_KEYPAIR_JSON='[<64 bytes>]'`
so you don't need a volume mount.

## Stack

| Layer | Technology |
|-------|-----------|
| Framework | Rails 8.1, Ruby 3.3.6 |
| Frontend | Hotwire (Turbo + Stimulus), Tailwind CSS 4, esbuild |
| Solana (server) | `solrengine-auth`, `solrengine-rpc`, `solrengine-programs` |
| Solana (client) | `@solana/kit`, `@solrengine/wallet-utils`, `@wallet-standard/app` |
| Database | SQLite + Solid Cache/Queue/Cable |
| Deploy | Kamal + Thruster |

## License

MIT
