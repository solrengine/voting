require "test_helper"

class Voting::PollSnapshotTest < ActiveSupport::TestCase
  class StubRpc
    def initialize(responses) = @responses = responses
    def request(_method, params)
      pubkey = params.first
      { "result" => { "value" => @responses[pubkey] } }
    end
  end

  def with_stub_rpc(responses)
    stub = StubRpc.new(responses)
    Solrengine::Rpc.singleton_class.alias_method :__orig_client, :client
    Solrengine::Rpc.define_singleton_method(:client) { |**| stub }
    yield
  ensure
    Solrengine::Rpc.singleton_class.alias_method :client, :__orig_client
    Solrengine::Rpc.singleton_class.remove_method :__orig_client
  end

  test "voting_state is :not_initialized when poll account is missing" do
    with_stub_rpc({}) do
      snap = Voting::PollSnapshot.current
      assert_equal :not_initialized, snap.voting_state
      assert_not snap.open?
    end
  end
end
