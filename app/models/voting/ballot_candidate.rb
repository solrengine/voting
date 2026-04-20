module Voting
  BallotCandidate = Data.define(:config, :address, :account) do
    def name        = config.name
    def description = config.description
    def url         = config.url
    def votes       = account&.candidate_votes.to_i
  end
end
