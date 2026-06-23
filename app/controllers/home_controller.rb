# frozen_string_literal: true

class HomeController < ApplicationController
  skip_before_action :require_login, only: [ :index ]
  def index
    @new_withdrawals_count = session[:role].to_s == "admin" ? WithdrawalRequest.new_items.count : 0
  end
end
