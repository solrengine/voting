class Voting::InitializePollInstruction < Solrengine::Programs::Instruction
  program_id Voting::PROGRAM_ID
  instruction_name "initialize_poll"

  argument :poll_id, "u64"
  argument :start_time, "u64"
  argument :end_time, "u64"
  argument :name, "string"
  argument :description, "string"

  account :signer, signer: true, writable: true
  account :poll_account, writable: true, pda: [
    { const: "poll".bytes },
    { arg: :poll_id, type: :u64 }
  ]
  account :system_program, address: "11111111111111111111111111111111"
end
