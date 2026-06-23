# frozen_string_literal: true

class AddStatusFieldsToWithdrawalRequests < ActiveRecord::Migration[7.2]
  def up
    add_column :withdrawal_requests, :status, :string, default: "new", null: false
    add_column :withdrawal_requests, :acknowledged_at, :datetime
    add_column :withdrawal_requests, :resolved_at, :datetime
    add_column :withdrawal_requests, :resolved_by, :string

    execute <<~SQL
      UPDATE withdrawal_requests
      SET status = 'new'
      WHERE status IS NULL OR status = ''
    SQL
  end

  def down
    remove_column :withdrawal_requests, :resolved_by
    remove_column :withdrawal_requests, :resolved_at
    remove_column :withdrawal_requests, :acknowledged_at
    remove_column :withdrawal_requests, :status
  end
end