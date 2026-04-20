namespace :voting do
  desc "Initialize the pinned poll on-chain from config/candidates.yml"
  task init_poll: :environment do
    Voting::CandidateConfig.reload!
    poll = Voting::CandidateConfig.poll
    kp = VotingKeypair.load!

    ix = Voting::InitializePollInstruction.new(
      poll_id: poll.id,
      start_time: poll.start_time,
      end_time: poll.end_time,
      name: poll.name,
      description: poll.description,
      signer: kp[:public_key_base58]
    )

    signature = Solrengine::Programs::TransactionBuilder.new
      .add_instruction(ix)
      .add_signer(kp)
      .sign_and_send

    puts "Initialized poll ##{poll.id}: #{signature}"
    puts "Solscan: https://solscan.io/tx/#{signature}?cluster=devnet"
  end

  desc "Verify config/candidates.yml matches on-chain state; exits 1 on drift"
  task verify: :environment do
    Voting::CandidateConfig.reload!
    poll     = Voting::CandidateConfig.poll
    snapshot = Voting::PollSnapshot.current
    account  = snapshot.poll_account
    abort "Poll ##{poll.id} not initialized on-chain" unless account

    drift = []
    drift << "name: yaml=#{poll.name.inspect} chain=#{account.poll_name.inspect}" if poll.name != account.poll_name
    drift << "description: yaml=#{poll.description.inspect} chain=#{account.poll_description.inspect}" if poll.description != account.poll_description
    drift << "start_time: yaml=#{poll.start_time} chain=#{account.poll_voting_start}" if poll.start_time.to_i != account.poll_voting_start.to_i
    drift << "end_time: yaml=#{poll.end_time} chain=#{account.poll_voting_end}" if poll.end_time.to_i != account.poll_voting_end.to_i

    snapshot.candidates.each do |cand|
      if cand.account.nil?
        drift << "candidate #{cand.name.inspect}: not initialized on-chain (PDA #{cand.address})"
      elsif cand.account.candidate_name != cand.name
        drift << "candidate #{cand.name.inspect}: chain name=#{cand.account.candidate_name.inspect}"
      end
    end

    if drift.empty?
      puts "OK — yaml matches on-chain poll ##{poll.id}"
    else
      puts "DRIFT detected between config/candidates.yml and on-chain state:"
      drift.each { |d| puts "  - #{d}" }
      abort
    end
  end

  desc "Initialize each candidate in config/candidates.yml on-chain"
  task init_candidates: :environment do
    Voting::CandidateConfig.reload!
    poll = Voting::CandidateConfig.poll
    kp = VotingKeypair.load!

    Voting::CandidateConfig.candidates.each do |candidate|
      ix = Voting::InitializeCandidateInstruction.new(
        poll_id: poll.id,
        candidate: candidate.name,
        signer: kp[:public_key_base58]
      )

      begin
        signature = Solrengine::Programs::TransactionBuilder.new
          .add_instruction(ix)
          .add_signer(kp)
          .sign_and_send
        puts "  #{candidate.name.ljust(16)} #{signature}"
      rescue Solrengine::Programs::TransactionError => e
        # Anchor's `init` fails loudly if the PDA already exists. Treat that as
        # idempotent — a candidate that's already initialized is fine.
        if e.message.include?("already in use")
          puts "  #{candidate.name.ljust(16)} (already initialized)"
        else
          raise
        end
      end
    end
  end
end

