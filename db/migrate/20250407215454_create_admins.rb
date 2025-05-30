# frozen_string_literal: true

class CreateAdmins < ActiveRecord::Migration[7.2]
  def change
    create_table :admins do |t|
      t.string :email

      t.timestamps
    end
    add_index :admins, :email, unique: true
  end
end
