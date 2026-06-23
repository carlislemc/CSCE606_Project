# frozen_string_literal: true

class WithdrawalRequest < ApplicationRecord
	STATUSES = %w[new acknowledged resolved].freeze

	validates :status, inclusion: { in: STATUSES }

	scope :new_items, -> { where(status: "new") }
	scope :open_items, -> { where(status: %w[new acknowledged]) }
	scope :recent_first, -> { order(created_at: :desc) }

	def open?
		status != "resolved"
	end
end
