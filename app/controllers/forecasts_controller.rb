# The Forecast page: the expected balance of the everyday accounts up to any
# date, from today's balances, the recurring movements, the one-off movements
# the user expects and, optionally, the usual variable spending.
class ForecastsController < ApplicationController
  # Shortcuts for the end date; any other date can be typed in.
  PERIODS = { "1m" => 1, "3m" => 3, "6m" => 6, "1y" => 12, "2y" => 24, "5y" => 60 }.freeze
  DEFAULT_PERIOD = "3m"
  MAX_LISTED_FLOWS = 300

  def show
    @accounts = forecast_accounts
    @period = params[:until].present? ? nil : (PERIODS.key?(params[:period]) ? params[:period] : DEFAULT_PERIOD)
    @through = custom_date || (Date.current >> PERIODS.fetch(@period || DEFAULT_PERIOD))
    @include_variable = params[:variable] != "0"
    @account = @accounts.find { |account| account.id == params[:account_id] }

    @forecast = Forecast.new(Current.family, accounts: @accounts, through: @through, include_variable: @include_variable)
    @forecast_items = Current.family.forecast_items.upcoming.where(account_id: @accounts.map(&:id)).includes(:account).chronological
  end

  private
    def forecast_accounts
      accessible_accounts.visible.where(accountable_type: Forecast::ACCOUNT_TYPES).alphabetically.to_a
    end

    # A date typed in the form, never before tomorrow.
    def custom_date
      date = Date.iso8601(params[:until].to_s)
      [ date, Date.current + 1 ].max
    rescue Date::Error
      nil
    end
end
