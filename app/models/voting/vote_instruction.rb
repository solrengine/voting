class Voting::VoteInstruction < Solrengine::Programs::Instruction
  program_id Voting::PROGRAM_ID
  instruction_name "vote"

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

  def to_wire_payload(blockhash:)
    built = to_instruction
    {
      program_id: built[:program_id],
      accounts: built[:accounts].map { |a| a.slice(:pubkey, :is_signer, :is_writable) },
      instruction_data: Base64.strict_encode64(built[:data]),
      blockhash: blockhash[:blockhash],
      last_valid_block_height: blockhash[:last_valid_block_height]
    }
  end
end
