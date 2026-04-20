require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "wallet_address must be unique" do
    User.create!(wallet_address: "DRpbCBMxVnDK7maPMoGQfFKoQNvz3GrAFVdVVNR3NHxz", nonce: "testnonce1")
    duplicate = User.new(wallet_address: "DRpbCBMxVnDK7maPMoGQfFKoQNvz3GrAFVdVVNR3NHxz", nonce: "testnonce2")
    assert_not duplicate.valid?
  end

  test "wallet_address must be present" do
    user = User.new(wallet_address: nil)
    assert_not user.valid?
  end
end
