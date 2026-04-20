require "test_helper"

class Voting::VoteInstructionTest < ActiveSupport::TestCase
  test "program_id points at the Voting::PROGRAM_ID constant" do
    assert_equal Voting::PROGRAM_ID, Voting::VoteInstruction.program_id
  end

  test "to_wire_payload returns JSON-serializable fields" do
    ix = Voting::VoteInstruction.new(
      poll_id: 2,
      candidate: "PiggyBank",
      signer: "8d3EQ8m7CxExC3xuEZMqQ5VPpyXrBz9rK8aQn1e3HHi1"
    )
    assert ix.valid?
    payload = ix.to_wire_payload(blockhash: { blockhash: "abc", last_valid_block_height: 12345 })
    assert_equal Voting::PROGRAM_ID, payload[:program_id]
    assert_equal "abc", payload[:blockhash]
    assert_equal 12345, payload[:last_valid_block_height]
    assert_kind_of String, payload[:instruction_data]
    assert_kind_of Array, payload[:accounts]
    assert payload[:accounts].first.key?(:pubkey)
  end
end
