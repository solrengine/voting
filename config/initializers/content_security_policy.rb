# Content Security Policy for a Solana dApp.
#  - connect-src allows the configured Solana RPC + WS endpoints and Jupiter.
#  - Wallet extensions inject content scripts that bypass page CSP, so no
#    additional allowances are needed for Phantom/Backpack/Solflare/etc.
# Override SOLANA_RPC_URL / SOLANA_WS_URL to point at a paid RPC provider
# (Helius/QuickNode/Triton/etc.) if devnet isn't good enough.

Rails.application.configure do
  config.content_security_policy do |policy|
    rpc_host = ENV.fetch("SOLANA_RPC_URL", "https://api.devnet.solana.com")
    ws_host  = ENV.fetch("SOLANA_WS_URL",  "wss://api.devnet.solana.com")

    policy.default_src     :self
    policy.font_src        :self, :data
    policy.img_src         :self, :data, :https
    policy.object_src      :none
    policy.script_src      :self
    # Turbo applies inline style attributes (progress bar, preview rendering).
    # CSP nonces and hashes don't apply to style *attributes* (only <style>
    # elements), so :unsafe_inline is required. Script execution remains
    # nonce-protected, which is what actually matters for XSS.
    policy.style_src       :self, :unsafe_inline
    policy.connect_src     :self, "https://api.jup.ag", rpc_host, ws_host
    policy.frame_ancestors :none
    policy.base_uri        :self
    policy.form_action     :self
  end

  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_report_only = false
end
