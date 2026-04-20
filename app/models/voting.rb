module Voting
  # Single source of truth for the on-chain voting program.
  # Override with VOTING_PROGRAM_ID env var when pointing at a new deployment.
  PROGRAM_ID = ENV.fetch("VOTING_PROGRAM_ID", "2F1Z4eTmFqbjAnNWaDXXScoBYLMFn1gTasVy2mfPTeJx")
end
