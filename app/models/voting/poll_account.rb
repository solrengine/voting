class Voting::PollAccount < Solrengine::Programs::Account
  program_id Voting::PROGRAM_ID
  account_name "PollAccount"

  borsh_field :poll_name, "string"
  borsh_field :poll_description, "string"
  borsh_field :poll_voting_start, "u64"
  borsh_field :poll_voting_end, "u64"
  borsh_field :poll_option_index, "u64"

  def starts_at = Time.at(poll_voting_start.to_i).utc
  def ends_at   = Time.at(poll_voting_end.to_i).utc

  def not_started?(now: Time.current) = now.to_i < poll_voting_start.to_i
  def ended?(now: Time.current)       = now.to_i > poll_voting_end.to_i
  def open?(now: Time.current)        = !not_started?(now: now) && !ended?(now: now)

  def voting_state(now: Time.current)
    return :not_started if not_started?(now: now)
    return :ended       if ended?(now: now)
    :open
  end
end
