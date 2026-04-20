# Deploying to Production

This app deploys with [Kamal](https://kamal-deploy.org). The Rails and Docker
configuration is ready; fill in your own values before the first deploy.

## Pre-deploy checklist

Run through these before `bin/kamal deploy`:

- [ ] No `path:` gems in `Gemfile`. Docker builds outside the app tree cannot
  resolve `path: "../solrengine-programs"`. Swap to `git:` (with a pinned
  SHA) or the published RubyGems version before deploying.
- [ ] `grep -n 'path:' Gemfile` returns nothing (other than comments).
- [ ] `config/master.key` exists locally and is referenced in `.kamal/secrets`.
- [ ] `APP_DOMAIN` env var matches your production hostname exactly (no
  scheme, no port).
- [ ] `bin/rails test` passes.
- [ ] `bin/rails voting:verify` passes (yaml ≡ chain) if the poll is already
  initialized.

## Prerequisites

- A server reachable over SSH (any Ubuntu/Debian VPS works)
- A container registry account (Docker Hub, GHCR, DigitalOcean, etc.)
- A domain pointed at the server with an A/AAAA record
- A funded Solana keypair on the target cluster (~0.1 SOL on devnet, more on
  mainnet) for initializing the poll + candidates on-chain after deploy

This app runs on devnet by default (public `api.devnet.solana.com`), so no
paid RPC provider is needed. If you switch `SOLANA_NETWORK` to mainnet, the
public endpoint is heavily rate-limited — use Helius, QuickNode, Triton, or
similar and inject the URL via `SOLANA_RPC_URL` / `SOLANA_WS_URL`.

## Step 1: generate Rails credentials

```sh
bin/rails credentials:edit
```

This creates `config/master.key` (gitignored) and `config/credentials.yml.enc`
(committed). **Back the key up securely** — losing it means losing every
encrypted value.

## Step 2: configure `config/deploy.yml`

Copy the example and fill in your values:

```sh
cp config/deploy.yml.example config/deploy.yml
```

| Key | What to set |
| --- | --- |
| `service` | Short app name, e.g. `my_solana_app` |
| `image`  | `your-user/my_solana_app` (must match registry path) |
| `servers.web` | Your server IP or hostname |
| `proxy.host` | Your production domain (e.g. `app.example.com`) |
| `proxy.ssl` | `true` (Kamal provisions Let's Encrypt automatically) |
| `registry.server` | `ghcr.io`, `docker.io`, `registry.digitalocean.com`, etc. |
| `env.clear.APP_DOMAIN` | Your production domain (same as `proxy.host`) |
| `ssh.user` | SSH user on the server |

Production SSL, DNS rebinding protection, HSTS, and mailer host are all
driven by the `APP_DOMAIN` env var in `config/environments/production.rb`.

## Step 3: set secrets

Create `.kamal/secrets` (it's gitignored). At minimum:

```sh
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
RAILS_MASTER_KEY=$(cat config/master.key)
```

Export the shell variables before deploying, or use a password manager
(1Password, Bitwarden CLI, etc.) — see the comments in
`.kamal/hooks/*.sample` for patterns.

## Step 4: deploy

```sh
bin/kamal setup     # first time — bootstraps Docker, pushes image, starts
bin/kamal deploy    # subsequent deploys
```

Watch logs with `bin/kamal logs`.

## Step 5: initialize the poll on-chain

The first time you deploy (or any time you want to start a fresh poll):

1. Edit `config/candidates.yml` with your poll id, window, and candidates.
   Commit + redeploy so the production container has the updated YAML.
2. From your **local machine** (not the server — the keypair stays off the
   production VM), point `SOLANA_KEYPAIR_FILE` at a Solana CLI keypair and
   run the rake tasks. These talk directly to the target cluster's RPC — no
   production Rails involvement:

   ```sh
   export SOLANA_KEYPAIR_FILE=~/.config/solana/id.json
   bin/rails voting:init_poll
   sleep 5
   bin/rails voting:init_candidates
   ```

3. Each task prints a Solscan link. Confirm the accounts exist before
   expecting the production page to render the poll correctly.

Important: never put `SOLANA_KEYPAIR_FILE` in production env or secrets. The
server-side keypair is only needed to **initialize** poll/candidate accounts;
runtime votes are signed by end-user wallets.

## Step 6: verify

- `https://your-domain/up` returns 200 (Rails health check)
- Landing page loads with styles intact
- Connect a wallet → redirects to `/poll` and shows the candidates + vote counts
- Cast a test vote → transaction lands on Solscan, count increments within a
  few seconds
- Open DevTools console → check for CSP violations. CSP is enforcing; any
  new asset sources need to be added to
  `config/initializers/content_security_policy.rb`

## Notes

- **SIWS signatures are tied to `APP_DOMAIN`.** If it doesn't match the URL
  the browser shows, wallet sign-in will fail. Must be the exact host — no
  scheme, no port (e.g. `app.example.com`).
- **SQLite + Solid Queue/Cache/Cable is single-server only.** The Kamal
  `volumes` block persists `/rails/storage`. For durability, add off-server
  backups (Litestream, rclone to S3, etc.).
- **`config/master.key` must never be committed.** It's in `.gitignore` and
  `.dockerignore`; double-check before pushing.
