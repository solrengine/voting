require "test_helper"

class Voting::PollAccountTest < ActiveSupport::TestCase
  def build(start_time:, end_time:)
    account = Voting::PollAccount.allocate
    account.instance_variable_set(:@attributes, {
      poll_name: "T", poll_description: "d",
      poll_voting_start: start_time, poll_voting_end: end_time,
      poll_option_index: 0
    })
    account.define_singleton_method(:poll_voting_start) { @attributes[:poll_voting_start] }
    account.define_singleton_method(:poll_voting_end)   { @attributes[:poll_voting_end] }
    account
  end

  test "not_started when now < start" do
    a = build(start_time: 1_000, end_time: 2_000)
    assert a.not_started?(now: Time.at(500))
    assert_not a.open?(now: Time.at(500))
    assert_equal :not_started, a.voting_state(now: Time.at(500))
  end

  test "open when start <= now <= end" do
    a = build(start_time: 1_000, end_time: 2_000)
    assert a.open?(now: Time.at(1_500))
    assert_equal :open, a.voting_state(now: Time.at(1_500))
  end

  test "ended when now > end" do
    a = build(start_time: 1_000, end_time: 2_000)
    assert a.ended?(now: Time.at(2_500))
    assert_not a.open?(now: Time.at(2_500))
    assert_equal :ended, a.voting_state(now: Time.at(2_500))
  end

  test "starts_at / ends_at return UTC times" do
    a = build(start_time: 1_776_297_600, end_time: 1_807_920_000)
    assert_equal 1_776_297_600, a.starts_at.to_i
    assert_equal 1_807_920_000, a.ends_at.to_i
    assert a.starts_at.utc?
  end
end
