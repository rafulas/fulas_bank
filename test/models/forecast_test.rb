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

  test "expects the instalments of an insurance paid in custom instalments every year, in its account" do
    today = Date.new(2026, 10, 1)
    other = create_account("Otra cuenta", Depository.new, balance: 500)
    insurance = @family.insurances.create!(
      name: "Seguro Cupra", kind: "car", payment_frequency: "custom", payment_account: other,
      installments: [
        { "date" => "2026-09-01", "amount" => "150" },
        { "date" => "2026-10-16", "amount" => "150" },
        { "date" => "2026-11-30", "amount" => "150" }
      ]
    )

    forecast = Forecast.new(@family, accounts: [ @account, other ], through: Date.new(2027, 12, 31), include_variable: false, today: today)
    lines = forecast.flows.select { |flow| flow.source == :insurance }

    assert_equal [ Date.new(2026, 10, 16), Date.new(2026, 11, 30), Date.new(2027, 9, 1), Date.new(2027, 10, 16), Date.new(2027, 11, 30) ], lines.map(&:date)
    assert lines.all? { |flow| flow.account == other && flow.amount == 150 }
    assert_includes lines.first.name, "Seguro Cupra"
    assert_equal 500 - 150 * 5, forecast.balances_on(Date.new(2027, 12, 31))[other].amount

    # A change to one year's instalment, from the table, stays on that line.
    @family.forecast_adjustments.create!(key: ForecastAdjustment.insurance_key(insurance, Date.new(2027, 9, 1)), amount: 160)
    changed = Forecast.new(@family, accounts: [ @account, other ], through: Date.new(2027, 12, 31), include_variable: false, today: today)
                      .flows.find { |flow| flow.date == Date.new(2027, 9, 1) && flow.source == :insurance }
    assert_equal 160, changed.amount
  end

  test "an insurance with no account set is expected in the main account, and only while in force" do
    insurance = @family.insurances.create!(
      name: "Seguro moto", kind: "motorcycle", payment_frequency: "custom",
      installments: [ { "date" => (Date.current + 5).iso8601, "amount" => "90" } ]
    )

    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.current + 30, include_variable: false)
    assert_equal [ @account ], forecast.flows.select { |flow| flow.source == :insurance }.map(&:account)

    insurance.update!(active: false)
    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.current + 30, include_variable: false)
    assert_empty forecast.flows.select { |flow| flow.source == :insurance }
  end

  test "warns of the first day the account drops below the cushion, and its lowest point" do
    @family.forecast_items.create!(account: @account, name: "Seguro coche", amount: 300, nature: "outflow", date: Date.current + 10)
    @family.forecast_items.create!(account: @account, name: "Viaje", amount: 500, nature: "outflow", date: Date.current + 20)
    @family.forecast_items.create!(account: @account, name: "Nómina", amount: 2_000, nature: "inflow", date: Date.current + 25)

    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.current + 30, include_variable: false)

    assert_equal [ Date.current + 20, Money.new(200, @account.currency) ], forecast.first_below(@account, 500)
    assert_nil forecast.first_below(@account, 100)
    assert_equal [ Date.current + 20, Money.new(200, @account.currency) ], forecast.lowest_balance(@account)
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

  test "adds a variable spending line at the end of each month, and this month only what is still to come" do
    today = Date.new(2026, 10, 14)
    create_transaction(account: @account, name: "Supermercado", amount: 300, date: Date.new(2026, 9, 10))
    create_transaction(account: @account, name: "Cena", amount: 100, date: Date.new(2026, 10, 5))

    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.new(2026, 12, 31), today: today)
    lines = forecast.flows.select { |flow| flow.source == :variable }

    assert_equal [ Date.new(2026, 10, 31), Date.new(2026, 11, 30), Date.new(2026, 12, 31) ], lines.map(&:date)
    assert_equal [ BigDecimal("200"), BigDecimal("300"), BigDecimal("300") ], lines.map(&:amount)
    assert_equal I18n.t("forecasts.variable_line", month: I18n.l(Date.new(2026, 11, 1), format: "%B %Y")), lines.second.name
    assert_equal 1_000 - 800, forecast.balances_on(Date.new(2026, 12, 31))[@account].amount

    without = Forecast.new(@family, accounts: [ @account ], through: Date.new(2026, 12, 31), include_variable: false, today: today)
    assert_empty without.flows
  end

  test "a line the user changes, leaves out or brings back" do
    create_series(@account, name: "Gimnasio", amount: 40)
    through = Date.current + 60
    first = Forecast.new(@family, accounts: [ @account ], through: through, include_variable: false).flows.first

    adjustment = @family.forecast_adjustments.create!(key: first.key, amount: 55, name: "Gimnasio nuevo", date: first.date + 1)
    changed = Forecast.new(@family, accounts: [ @account ], through: through, include_variable: false)
    line = changed.flows.find { |flow| flow.key == first.key }

    assert_equal [ BigDecimal("55"), "Gimnasio nuevo", first.date + 1, true ], [ line.amount, line.name, line.date, line.adjusted ]

    adjustment.update!(skipped: true)
    skipped = Forecast.new(@family, accounts: [ @account ], through: through, include_variable: false)

    assert skipped.flows.find { |flow| flow.key == first.key }.skipped
    assert_not_includes skipped.active_flows.map(&:key), first.key
    assert_equal 1_000 - 40 * skipped.active_flows.size, skipped.balances_on(through)[@account].amount

    adjustment.destroy!
    restored = Forecast.new(@family, accounts: [ @account ], through: through, include_variable: false)
    assert_equal first, restored.flows.first
  end

  test "the table carries the balance after each line" do
    @family.forecast_items.create!(account: @account, name: "Viaje", amount: 300, nature: "outflow", date: Date.current + 5)
    @family.forecast_items.create!(account: @account, name: "Devolución", amount: 100, nature: "inflow", date: Date.current + 9)

    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.current + 30, include_variable: false)
    rows = forecast.ledger

    assert_equal [ 700, 800 ], rows.map { |row| row.balances[@account.id].to_i }
    assert_equal [ 700, 800 ], rows.map { |row| row.total.amount.to_i }
    assert_equal [ -300, 100 ], rows.map { |row| forecast.user_amount(row.flow).amount.to_i }
    assert rows.all? { |row| row.flow.record.is_a?(ForecastItem) }
  end

  test "a series that ends is not projected beyond its end" do
    series = create_series(@account, name: "Préstamo", amount: 100)
    series.update!(end_mode: "on_date", end_on: Date.current + 70)

    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.current + 400, include_variable: false)
    dates = forecast.flows.select { |flow| flow.name == "Préstamo" }.map(&:date)

    assert dates.any?
    assert dates.all? { |date| date <= Date.current + 70 }
  end

  test "cards are not shown: their charges are expected in the main account, and paying them off is left out" do
    savings = create_account("Forecast savings", Depository.new, balance: 500)
    card = create_account("Forecast card", CreditCard.new, balance: 200)
    create_series(card, name: "Streaming", amount: 10)
    create_series(@account, name: "Pago tarjeta", amount: 300, destination_account: card)

    forecast = Forecast.new(@family, accounts: [ savings, @account, card ], card_accounts: [ card ], main_account: @account,
                            through: Date.current + 31, include_variable: false)
    charges = forecast.flows.select { |flow| flow.name == "Streaming" }

    assert_equal [ savings, @account ], forecast.accounts
    assert charges.any?
    assert charges.all? { |flow| flow.account == @account }
    assert_empty forecast.flows.select { |flow| flow.name == "Pago tarjeta" }
    assert_equal 1_000 - 10 * charges.size, forecast.balances_on(Date.current + 31)[@account].amount
  end

  test "the variable spending of every account and card is one line in the main account" do
    today = Date.new(2026, 10, 14)
    savings = create_account("Forecast savings", Depository.new, balance: 500)
    card = create_account("Forecast card", CreditCard.new, balance: 0)
    create_transaction(account: @account, name: "Súper", amount: 300, date: Date.new(2026, 9, 10))
    create_transaction(account: card, name: "Cena", amount: 100, date: Date.new(2026, 9, 12))

    forecast = Forecast.new(@family, accounts: [ savings, @account ], card_accounts: [ card ], main_account: savings,
                            through: Date.new(2026, 11, 30), today: today)
    lines = forecast.flows.select { |flow| flow.source == :variable }

    assert_equal [ savings, savings ], lines.map(&:account)
    assert_equal [ BigDecimal("400"), BigDecimal("400") ], lines.map(&:amount)
  end

  test "the main account defaults to the first current account" do
    savings = create_account("Forecast savings", Depository.new, balance: 500)
    forecast = Forecast.new(@family, accounts: [ @account, savings ], through: Date.current + 31)

    assert_equal @account, forecast.main_account
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

  test "the debt plan's payments replace the loan's recurring payment from next month" do
    loan = create_account("Préstamo coche", Loan.new(interest_rate: 0, payment_amount: 100, payment_day: 5), balance: 1_000)
    series = create_series(@account, name: "Cuota coche", amount: 100)
    # The family's mortgage (a fixture) is left out, so only this loan counts.
    plan = @family.create_debt_plan!(feeds_forecast: true, loan_settings: {
      loan.id => { "recurring_transaction_id" => series.id }, accounts(:loan).id => { "excluded" => "1" }
    })
    plan.extra_payments.create!(date: (Date.current >> 2).beginning_of_month + 19, amount: 300, name: "Bonus")

    forecast = Forecast.new(@family, accounts: [ @account ], through: Date.current >> 12, include_variable: false,
                            debt_plan: plan.forecast_feed(users(:family_admin)))
    next_month = Date.current.next_month.beginning_of_month

    assert forecast.flows.none? { |flow| flow.name == "Cuota coche" && flow.date >= next_month }
    plan_lines = forecast.flows.select { |flow| flow.source == :debt_plan }
    assert_equal next_month + 4, plan_lines.first.date
    assert plan_lines.any? { |flow| flow.amount == 300 && flow.name.include?("Bonus") }
    assert_equal BigDecimal("1000"), plan_lines.sum(&:amount)
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
