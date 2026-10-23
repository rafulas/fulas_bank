# The Forecast page: the expected balance of the everyday accounts up to any
# date (five years by default), from today's balances, the recurring
# movements, the one-off movements the user expects and, optionally, the
# usual variable spending; with the table of every expected line, which the
# user can edit.
class ForecastsController < ApplicationController
  # Shortcuts for the end date; any other date can be typed in.
  PERIODS = { "1m" => 1, "3m" => 3, "6m" => 6, "1y" => 12, "2y" => 24, "5y" => 60 }.freeze
  DEFAULT_PERIOD = "5y"

  # Fulas Bank: each loan's instalment, kept in step with the loan (and a
  # loan paid twice, by its own movement and by one from the bank, merged).
  before_action :sync_loan_installments, only: %i[show table]
  before_action :build_forecast, except: %i[update_columns update_variable_accounts]

  def show
  end

  # The table on its own, in a wide dialog, to see every column at once.
  def table
  end

  # Fulas Bank: "Editar tabla": the accounts shown as columns and the group
  # each one adds up in (cash, savings and investments, or none).
  def edit_columns
  end

  def update_columns
    accounts = forecast_accounts
    shown = Array(params[:shown]).map(&:to_s)
    # Every account gets a value, so a group set before is always replaced.
    groups = accounts.to_h do |account|
      chosen = params.dig(:groups, account.id).to_s
      [ account.id, Forecast::GROUPS.include?(chosen) ? chosen : Forecast.default_group(account) ]
    end

    Current.user.update_dashboard_preferences(
      Forecast::HIDDEN_COLUMNS_PREFERENCE => accounts.map(&:id).reject { |id| shown.include?(id) },
      Forecast::COLUMN_GROUPS_PREFERENCE => groups
    )

    redirect_back_or_to forecast_path, notice: t(".success")
  end

  # Fulas Bank: «Ver cálculo» of a month's "Gastos varios": the months
  # averaged, the categories behind them and, for one category, its
  # movements; and which accounts count.
  def variable
    @month = variable_month
    @breakdown = Forecast::VariableBreakdown.new(Current.family, accounts: @forecast.variable_accounts, month: @month)
    @category_row = @breakdown.category_row(params[:category]) if params[:category].present?
    @variable_candidates = @forecast.counted_accounts + @forecast.card_accounts
  end

  def update_variable_accounts
    candidates = forecast_accounts + card_accounts
    counted = Array(params[:counted]).map(&:to_s)

    Current.user.update_dashboard_preferences(
      Forecast::VARIABLE_EXCLUDED_PREFERENCE => candidates.map { |account| account.id.to_s }.reject { |id| counted.include?(id) }
    )

    redirect_back_or_to forecast_path, notice: t(".success")
  end

  private
    def build_forecast
      @accounts = forecast_accounts
      @period = params[:until].present? ? nil : (PERIODS.key?(params[:period]) ? params[:period] : DEFAULT_PERIOD)
      @through = custom_date || (Date.current >> PERIODS.fetch(@period || DEFAULT_PERIOD))
      @include_variable = params[:variable] != "0"
      @account = @accounts.find { |account| account.id == params[:account_id] }
      @main_account = main_account
      @cushion = cushion

      @forecast = Forecast.new(Current.family, accounts: @accounts, through: @through, include_variable: @include_variable,
                               main_account: @main_account, card_accounts: card_accounts,
                               debt_plan: Current.family.debt_plan&.forecast_feed(Current.user),
                               column_groups: Current.user.preferences&.dig(Forecast::COLUMN_GROUPS_PREFERENCE) || {},
                               variable_excluded_ids: Forecast.variable_excluded_ids(Current.user, Current.family, @accounts + card_accounts))
      @hidden_columns = Array(Current.user.preferences&.dig(Forecast::HIDDEN_COLUMNS_PREFERENCE))
    end

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

    # The least the main account should have. Typing it in the form keeps it
    # for next time; leaving it empty removes it.
    def cushion
      if params.key?(:cushion)
        value = params[:cushion].to_s.tr(",", ".").presence&.to_d
        value = nil unless value&.positive?
        Current.user.update_dashboard_preferences(Forecast::CUSHION_PREFERENCE => value&.to_s("F"))
        return value
      end

      Current.user.preferences&.dig(Forecast::CUSHION_PREFERENCE).presence&.to_d
    end

    # The month asked for in «Ver cálculo», this month by default.
    def variable_month
      Date.iso8601(params[:month].to_s).beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end

    # A date typed in the form, never before tomorrow.
    def custom_date
      date = Date.iso8601(params[:until].to_s)
      [ date, Date.current + 1 ].max
    rescue Date::Error
      nil
    end

    def sync_loan_installments
      Loan::InstallmentSync.new(Current.family, user: Current.user).sync!
    end
end
