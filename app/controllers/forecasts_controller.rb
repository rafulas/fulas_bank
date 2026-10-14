# The Forecast page: the expected balance of the everyday accounts up to any
# date (five years by default), from today's balances, the recurring
# movements, the one-off movements the user expects and, optionally, the
# usual variable spending; with the table of every expected line, which the
# user can edit.
class ForecastsController < ApplicationController
  # Shortcuts for the end date; any other date can be typed in.
  PERIODS = { "1m" => 1, "3m" => 3, "6m" => 6, "1y" => 12, "2y" => 24, "5y" => 60 }.freeze
  DEFAULT_PERIOD = "5y"

  def show
    @accounts = forecast_accounts
    @period = params[:until].present? ? nil : (PERIODS.key?(params[:period]) ? params[:period] : DEFAULT_PERIOD)
    @through = custom_date || (Date.current >> PERIODS.fetch(@period || DEFAULT_PERIOD))
    @include_variable = params[:variable] != "0"
    @account = @accounts.find { |account| account.id == params[:account_id] }
    @main_account = main_account

    @forecast = Forecast.new(Current.family, accounts: @accounts, through: @through, include_variable: @include_variable,
                             main_account: @main_account, card_accounts: card_accounts)
  end

  private
    def forecast_accounts
      accessible_accounts.visible.where(accountable_type: Forecast::ACCOUNT_TYPES).alphabetically.to_a
    end

    def card_accounts
      accessible_accounts.visible.where(accountable_type: Forecast::CARD_TYPES).to_a
    end

    # The account where the monthly variable spending and the card charges
    # are expected. Choosing one in the form keeps it for next time.
    def main_account
      chosen = @accounts.find { |account| account.id == params[:main_account_id].to_s } if params[:main_account_id].present?
      if chosen
        Current.user.update_dashboard_preferences(Forecast::MAIN_ACCOUNT_PREFERENCE => chosen.id)
        return chosen
      end

      saved = Current.user.preferences&.dig(Forecast::MAIN_ACCOUNT_PREFERENCE)
      @accounts.find { |account| account.id == saved } || Forecast.default_main_account(@accounts)
    end

    # A date typed in the form, never before tomorrow.
    def custom_date
      date = Date.iso8601(params[:until].to_s)
      [ date, Date.current + 1 ].max
    rescue Date::Error
      nil
    end
end
