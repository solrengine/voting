class Voting::InitializeCandidateInstruction < Solrengine::Programs::Instruction
  program_id Voting::PROGRAM_ID
  instruction_name "initialize_candidate"

  argument :poll_id, "u64"
  argument :candidate, "string"

  account :signer, signer: true, writable: true
  account :poll_account, writable: true, pda: [
    { const: "poll".bytes },
    { arg: :poll_id, type: :u64 }
  ]
  account :candidate_account, writable: true, pda: [
    { arg: :poll_id, type: :u64 },
    { arg: :candidate, type: :string }
  ]
  account :system_program, address: "11111111111111111111111111111111"
end
