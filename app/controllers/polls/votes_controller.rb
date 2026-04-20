class Polls::VotesController < ApplicationController
  rate_limit to: 30, within: 1.minute, only: :create,
    with: -> { render json: { error: "Too many requests" }, status: :too_many_requests }
  rate_limit to: 120, within: 1.minute, only: :show,
    with: -> { render json: { error: "Too many requests" }, status: :too_many_requests }

  # Returns the confirmation status of a submitted vote signature. Used by
  # the Stimulus controller to poll for on-chain confirmation instead of a
  # fixed-delay reload.
  def show
    signature = params[:signature].to_s
    unless signature.match?(/\A[1-9A-HJ-NP-Za-km-z]{32,128}\z/)
      return render json: { error: "Invalid signature", code: "invalid_signature" },
                    status: :unprocessable_entity
    end

    status = Solrengine::Rpc.client.get_signature_status(signature) || {}
    render json: {
      signature: signature,
      confirmation_status: status["confirmationStatus"],
      err: status["err"],
      slot: status["slot"]
    }
  end

  def create
    candidate_name = params.require(:candidate).to_s
    poll_config = Voting::CandidateConfig.poll

    unless Voting::CandidateConfig.candidate_names.include?(candidate_name)
      return render json: { error: "Unknown candidate", code: "unknown_candidate" },
                    status: :unprocessable_entity
    end

    # Solana PDA seeds are capped at 32 bytes.
    if candidate_name.bytesize > 32
      return render json: { error: "Candidate name too long", code: "candidate_too_long" },
                    status: :unprocessable_entity
    end

    snapshot = Voting::PollSnapshot.current
    unless snapshot.open?
      return render json: { error: "Voting is not open", code: snapshot.voting_state.to_s },
                    status: :conflict
    end

    ix = Voting::VoteInstruction.new(
      poll_id: poll_config.id,
      candidate: candidate_name,
      signer: current_user.wallet_address
    )

    unless ix.valid?
      return render json: { error: ix.errors.join(", "), code: "invalid_instruction" },
                    status: :unprocessable_entity
    end

    render json: ix.to_wire_payload(blockhash: latest_blockhash)
  end

  private

  # Blockhashes are valid for ~60s on mainnet; caching for 20s saves an RPC
  # round-trip per vote click while staying well under expiry.
  def latest_blockhash
    Rails.cache.fetch("voting:latest_blockhash", expires_in: 20.seconds) do
      Rails.logger.tagged("solana-rpc") do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        bh = Solrengine::Rpc.client.get_latest_blockhash(commitment: "finalized")
        ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        Rails.logger.info("getLatestBlockhash duration=#{ms}ms")
        bh
      end
    end
  end
end
