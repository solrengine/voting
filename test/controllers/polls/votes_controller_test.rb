require "test_helper"

class Polls::VotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(wallet_address: "8d3EQ8m7CxExC3xuEZMqQ5VPpyXrBz9rK8aQn1e3HHi1")
    # Simulate authenticated session.
    post poll_prepare_vote_path # trigger controller init
  rescue
    # ignore; we'll set session in a test-level integration helper
  end

  test "unauthenticated JSON POST returns 401 with code" do
    post poll_prepare_vote_path, params: { candidate: "PiggyBank" }, as: :json
    assert_response :unauthorized
    assert_equal "unauthenticated", JSON.parse(response.body).fetch("code")
  end

  test "unauthenticated HTML POST redirects to login" do
    post poll_prepare_vote_path, params: { candidate: "PiggyBank" }
    assert_redirected_to solrengine_auth.login_path
  end
end
