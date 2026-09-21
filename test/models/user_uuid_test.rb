require "test_helper"

class UserUuidTest < ActiveSupport::TestCase
  test "users receive distinct persistent UUIDs" do
    first = User.create!
    second = User.create!
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, first.uuid)
    assert_not_equal first.uuid, second.uuid
    assert_equal first.uuid, first.reload.uuid
  end

  test "model and database require unique UUIDs" do
    user = User.create!
    assert_not User.new(uuid: user.uuid).valid?
    assert_not User.new(uuid: nil).valid?
    assert_not User.new(uuid: "not-a-uuid").valid?
    assert_raises(ActiveRecord::NotNullViolation) { user.update_column(:uuid, nil) }
    user.reload
    other = User.create!
    assert_raises(ActiveRecord::RecordNotUnique) { other.update_column(:uuid, user.uuid) }
  end

  test "seeds create user one and keep the same URL on repeated runs" do
    load Rails.root.join("db/seeds.rb")
    uuid = User.find(1).uuid
    assert_no_difference "User.count" do
      load Rails.root.join("db/seeds.rb")
    end
    assert_equal uuid, User.find(1).uuid
  end
end
