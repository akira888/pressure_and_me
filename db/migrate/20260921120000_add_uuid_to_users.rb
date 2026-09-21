class AddUuidToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :uuid, :string

    user_class = Class.new(ActiveRecord::Base) { self.table_name = "users" }
    user_class.reset_column_information
    user_class.find_each { |user| user.update_columns(uuid: SecureRandom.uuid) }

    add_index :users, :uuid, unique: true
    change_column_null :users, :uuid, false
  end

  def down
    remove_column :users, :uuid
  end
end
