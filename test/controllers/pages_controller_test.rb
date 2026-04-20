require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "should get home page" do
    get root_url
    assert_response :success
  end

  test "should get login page" do
    get solrengine_auth.login_url
    assert_response :success
  end
end
