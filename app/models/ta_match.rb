# frozen_string_literal: true

class TaMatch < ApplicationRecord
    belongs_to :applicant, primary_key: :uin, foreign_key: :uin, optional: true
    after_initialize :set_default_confirm, if: :new_record?

  private

  def set_default_confirm
    self.confirm ||= false
  end
end
