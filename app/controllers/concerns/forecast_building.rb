# Fulas Bank: how a Forecast is put together for the current user (its
# accounts, cards, main account, debt plan, columns and "Gastos varios"
# choices), shared by the Forecast page and its scenarios so both work out
# exactly the same forecast.
module ForecastBuilding
  extend ActiveSupport::Concern

  private
    def build_forecast_for(accounts:, through:, main_account:, include_variable: true, scenario: nil)
      Forecast.new(Current.family, accounts: accounts, through: through, include_variable: include_variable,
                   main_account: main_account, card_accounts: card_accounts,
                   debt_plan: Current.family.debt_plan&.forecast_feed(Current.user),
                   column_groups: Current.user.preferences&.dig(Forecast::COLUMN_GROUPS_PREFERENCE) || {},
                   variable_excluded_ids: Forecast.variable_excluded_ids(Current.user, Current.family, accounts + card_accounts),
                   variable_plan: variable_plan, scenario: scenario)
    end

    def forecast_accounts
      @forecast_accounts ||= accessible_accounts.visible.where(accountable_type: Forecast::ACCOUNT_TYPES).alphabetically.to_a
    end

    def card_accounts
      @card_accounts ||= accessible_accounts.visible.where(accountable_type: Forecast::CARD_TYPES).to_a
    end

    def variable_plan
      @variable_plan ||= Forecast::VariablePlan.new(Current.family, user: Current.user)
    end

    # The main account the user chose last in the Forecast, or the default.
    def saved_main_account(accounts)
      saved = Current.user.preferences&.dig(Forecast::MAIN_ACCOUNT_PREFERENCE)
      accounts.find { |account| account.id == saved } || Forecast.default_main_account(accounts)
    end

    def sync_loan_installments
      ActiveSupport::Notifications.instrument("part.fulas", part: "forecast.sincronizar_prestamos") do
        Loan::InstallmentSync.new(Current.family, user: Current.user).sync!
      end
    end
end
