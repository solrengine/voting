require "base58"
require "json"

# Tiny keypair loader used by the voting:* rake tasks.
# Accepts either SOLANA_KEYPAIR_FILE (a path to a Solana CLI json-array
# keypair) or SOLANA_KEYPAIR_JSON (the raw json-array string). The latter
# lets containerized agents pass a keypair via env without a volume mount.
module VotingKeypair
  def self.load!
    raw = keypair_source
    bytes = JSON.parse(raw).pack("C*")
    raise "Keypair must be 64 bytes (got #{bytes.bytesize})" unless bytes.bytesize == 64

    {
      secret_key: bytes[0, 32],
      public_key: bytes[32, 32],
      public_key_base58: Base58.binary_to_base58(bytes[32, 32], :bitcoin)
    }
  end

  def self.keypair_source
    if (json = ENV["SOLANA_KEYPAIR_JSON"])
      json.strip
    elsif (path = ENV["SOLANA_KEYPAIR_FILE"])
      File.read(File.expand_path(path)).strip
    else
      raise "Set SOLANA_KEYPAIR_FILE (path) or SOLANA_KEYPAIR_JSON (raw json array)"
    end
  end
end
