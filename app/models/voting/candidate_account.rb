class Voting::CandidateAccount < Solrengine::Programs::Account
  program_id Voting::PROGRAM_ID
  account_name "CandidateAccount"

  borsh_field :candidate_name, "string"
  borsh_field :candidate_votes, "u64"
end
