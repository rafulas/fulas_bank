require "test_helper"

class ForecastTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = create_account("Forecast checking", Depository.new, balance: 1_000)
  end

  test "adds a monthly bill for as long as asked, beyond the occurrences already scheduled" do
    create_series(@account, name: "Gimnasio", amount: 40)

    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.current + 400, include_variable: false)
    flows = forecast.flows.select { |flow| flow.name == "Gimnasio" }

    assert_operator flows.size, :>=, 13
    assert_equal flows.map(&:date).uniq.size, flows.size, "no month is counted twice"
    assert flows.all? { |flow| flow.date > Date.current }
    assert_equal 1_000 - 40 * flows.size, forecast.balances_on(Date.current + 400)[@account].amount
  end

  test "a salary brings money in" do
    create_series(@account, name: "Nómina", amount: -2_000)

    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.current + 31, include_variable: false)
    paydays = forecast.flows.count { |flow| flow.name == "Nómina" }

    assert_operator paydays, :>=, 1
    assert forecast.flows.all?(&:inflow?)
    assert_equal 1_000 + 2_000 * paydays, forecast.balances_on(Date.current + 31)[@account].amount
  end

  test "one-off movements count on their date" do
    @family.forecast_items.create!(account: @account, name: "Devolución renta", amount: 300, nature: "inflow", date: Date.current + 10)
    @family.forecast_items.create!(account: @account, name: "Viaje", amount: 500, nature: "outflow", date: Date.current + 20)

    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.current + 30, include_variable: false)

    assert_equal 1_000, forecast.balances_on(Date.current + 9)[@account].amount
    assert_equal 1_300, forecast.balances_on(Date.current + 10)[@account].amount
    assert_equal 800, forecast.balances_on(Date.current + 30)[@account].amount
    assert_equal %i[planned planned], forecast.flows.map(&:source)
  end

  test "spreads the average variable spending, leaving out transfers and one-off purchases" do
    last_month = (Date.current << 1).beginning_of_month + 5
    create_transaction(account: @account, name: "Supermercado", amount: 300, date: last_month)
    create_transaction(account: @account, name: "A ahorro", amount: 1_000, date: last_month, kind: "funds_movement")
    create_transaction(account: @account, name: "Sofá", amount: 900, date: last_month, kind: "one_time")

    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.current + 60)

    assert_equal BigDecimal("300"), forecast.variable_monthly[@account]
    assert_in_delta 1_000 - 600, forecast.balances_on(Date.current + 60)[@account].amount, 30

    without = Forecast.new(@family, accounts: [ @account ], through: Date.current + 60, include_variable: false)
    assert_equal 1_000, without.balances_on(Date.current + 60)[@account].amount
  end

  test "a card's debt grows with its charges, and the total subtracts it" do
    card = create_account("Forecast card", CreditCard.new, balance: 200)
    create_series(card, name: "Streaming", amount: 10)

    forecast = Forecast.new(@family, accounts: [ @account, card ], through: Date.current + 31, include_variable: false)
    charges = forecast.flows.count { |flow| flow.account == card }

    assert_equal 200 + 10 * charges, forecast.balances_on(Date.current + 31)[card].amount
    assert_equal 1_000 - (200 + 10 * charges), forecast.total_on(Date.current + 31).amount
  end

  test "a recurring transfer leaves one account and reaches the other" do
    savings = create_account("Forecast savings", Depository.new, balance: 0)
    create_series(@account, name: "Ahorro mensual", amount: 100, destination_account: savings)

    forecast = Forecast.new(@family, accounts: [ @account, savings ], through: Date.current + 31, include_variable: false)
    months = forecast.flows.count { |flow| flow.account == savings }

    assert_operator months, :>=, 1
    assert_equal 100 * months, forecast.balances_on(Date.current + 31)[savings].amount
    assert_equal 1_000, forecast.total_on(Date.current + 31).amount
  end

  test "draws one point a week for long horizons" do
    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.current + 5.years, include_variable: false)

    series = forecast.series
    assert_operator series.values.size, :<, 300
    assert_equal Date.current + 5.years, series.values.last.date
  end

  private
    def create_account(name, accountable, balance:)
      Account.create!(family: @family, owner: users(:family_admin), name: name, balance: balance, currency: "USD",
                      accountable: accountable, status: "active").reload
    end

    def create_series(account, name:, amount:, destination_account: nil)
      @family.recurring_transactions.create!(
        account: account, destination_account: destination_account, name: name, amount: amount,
        currency: "USD", expected_day_of_month: 15, status: "active", manual: true,
        bill_type: (destination_account ? nil : (amount.negative? ? "income" : "bill")), last_occurrence_date: Date.current,
        next_expected_date: Date.current
      )
    end
end
