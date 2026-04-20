module Voting
  # Value object that loads the current poll + candidate state from chain
  # and merges it with the YAML presentation config. One snapshot per request.
  # Uses a single getMultipleAccounts round-trip for the poll + every
  # candidate, so devnet sees one RPC call per page load regardless of N.
  class PollSnapshot
    def self.current = new(CandidateConfig.poll)

    def initialize(poll_config)
      @poll_config = poll_config
    end

    attr_reader :poll_config

    def program_id = PROGRAM_ID

    def poll_account   = loaded[:poll]
    def candidates     = loaded[:candidates]

    def voting_state(now: Time.current)
      return :not_initialized if poll_account.nil?
      poll_account.voting_state(now: now)
    end

    def open?(now: Time.current)
      voting_state(now: now) == :open
    end

    def as_json(*)
      {
        poll: {
          id: poll_config.id,
          name: poll_account&.poll_name || poll_config.name,
          description: poll_account&.poll_description || poll_config.description,
          starts_at: poll_account&.starts_at&.iso8601,
          ends_at: poll_account&.ends_at&.iso8601
        },
        state: voting_state.to_s,
        program_id: program_id,
        candidates: candidates.map do |c|
          {
            name: c.name,
            description: c.description,
            url: c.url,
            address: c.address,
            votes: c.votes
          }
        end
      }
    end

    private

    def loaded
      @loaded ||= load_accounts
    end

    def load_accounts
      poll_address = poll_pda
      candidate_configs = CandidateConfig.candidates
      candidate_addresses = candidate_configs.map { |cfg| candidate_pda(cfg.name) }
      all_addresses = [ poll_address, *candidate_addresses ]

      values = fetch_multiple(all_addresses)

      poll = decode(PollAccount, poll_address, values[0])
      cands = candidate_configs.each_with_index.map do |cfg, i|
        BallotCandidate.new(
          config: cfg,
          address: candidate_addresses[i],
          account: decode(CandidateAccount, candidate_addresses[i], values[i + 1])
        )
      end
      { poll: poll, candidates: cands }
    end

    def poll_pda
      @poll_pda ||= Solrengine::Programs::Pda.find_program_address(
        [ "poll".b, [ poll_config.id ].pack("Q<") ],
        program_id
      ).first
    end

    def candidate_pda(name)
      Solrengine::Programs::Pda.find_program_address(
        [ [ poll_config.id ].pack("Q<"), name.b ],
        program_id
      ).first
    end

    def fetch_multiple(addresses)
      Rails.logger.tagged("solana-rpc") do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = Solrengine::Rpc.client.request("getMultipleAccounts", [
          addresses, { "encoding" => "base64", "commitment" => "confirmed" }
        ])
        ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        Rails.logger.info("getMultipleAccounts n=#{addresses.length} duration=#{ms}ms")
        result.dig("result", "value") || Array.new(addresses.length)
      end
    rescue Solrengine::Rpc::Error => e
      Rails.logger.warn("getMultipleAccounts failed: #{e.class}: #{e.message}")
      Rails.error.report(e, context: { addresses: addresses })
      Array.new(addresses.length)
    end

    def decode(klass, pubkey, value)
      return nil unless value && (data = value.dig("data", 0))
      klass.from_account_data(pubkey, data, lamports: value["lamports"])
    rescue Solrengine::Programs::Error => e
      Rails.logger.warn("decode failed for #{pubkey}: #{e.class}: #{e.message}")
      Rails.error.report(e, context: { pubkey: pubkey, klass: klass.name })
      nil
    end
  end
end
