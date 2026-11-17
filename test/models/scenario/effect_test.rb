require "test_helper"

class Scenario::EffectTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @today = Date.current
    @account = Account.create!(family: @family, owner: users(:family_admin), name: "Escenario corriente", balance: 10_000,
                               currency: "USD", accountable: Depository.new, status: "active")
    Loan.update_all(payment_amount: nil, term_months: nil)
    @scenario = @family.scenarios.create!(name: "Prueba")
    @start = (@today >> 3).beginning_of_month
  end

  test "a stopped recurring movement is no longer expected between its dates" do
    series = create_series("Gimnasio", 40)
    @scenario.scenario_changes.create!(kind: "stop_recurring", recurring_transaction: series, starts_on: @start, ends_on: @start >> 2)

    dates = flows_named("Gimnasio").map(&:date)

    assert dates.any? { |date| date < @start }
    assert dates.none? { |date| date >= @start && date <= (@start >> 2) }
    assert dates.any? { |date| date > (@start >> 2) }
  end

  test "a recurring movement can change its amount from a date" do
    series = create_series("Seguro hogar", 50)
    @scenario.scenario_changes.create!(kind: "change_amount", recurring_transaction: series, starts_on: @start, amount: 65)

    lines = flows_named("Seguro hogar")

    assert lines.select { |flow| flow.date < @start }.all? { |flow| flow.amount == 50 }
    assert lines.select { |flow| flow.date >= @start }.all? { |flow| flow.amount == 65 }
  end

  test "a cancelled loan stops its payments and its payoff goes out that day" do
    loan_account = Account.create!(family: @family, owner: users(:family_admin), name: "Préstamo coche", balance: 8_000, currency: "USD",
                                   accountable: Loan.new(payment_amount: 300, payment_day: 5), status: "active")
    # Without its recurring movement, the forecast expects the instalment
    # from the loan itself, in the main account.
    @family.recurring_transactions.where(loan_account: loan_account).destroy_all

    @scenario.scenario_changes.create!(kind: "cancel_loan", loan_account: loan_account, starts_on: @start, payoff_mode: "manual", amount: 7_000)
    flows = forecast(scenario: @scenario).flows
    loan_lines = flows.select { |flow| flow.source == :loan && flow.origin == loan_account.id }

    assert loan_lines.any? { |flow| flow.date < @start }
    assert loan_lines.none? { |flow| flow.date >= @start }

    payoff = flows.find { |flow| flow.source == :scenario }
    assert_equal @start, payoff.date
    assert_equal 7_000, payoff.amount
    assert_equal @account, payoff.account
  end

  test "a loan's payoff can be what is left to pay that day" do
    loan_account = accounts(:loan)
    change = @scenario.scenario_changes.create!(kind: "cancel_loan", loan_account: loan_account, starts_on: @start)

    assert change.pending_loan_balance.positive?
    assert_equal change.pending_loan_balance, change.payoff_amount
    assert_equal change.pending_loan_balance, forecast(scenario: @scenario).flows.find { |flow| flow.source == :scenario }.amount
  end

  test "an added income comes every month until its end date" do
    @scenario.scenario_changes.create!(kind: "add_movement", name: "Alquiler plaza", nature: "inflow", frequency: "monthly",
                                       amount: 90, starts_on: @start, ends_on: @start >> 2)

    lines = forecast(scenario: @scenario).flows.select { |flow| flow.source == :scenario }

    assert_equal [ @start, @start >> 1, @start >> 2 ], lines.map(&:date)
    assert lines.all? { |flow| flow.amount == -90 && flow.inflow? }
  end

  test "the comparison shows the monthly saving and when a payoff is paid back" do
    series = create_series("Préstamo moto", 500)
    @scenario.scenario_changes.create!(kind: "stop_recurring", recurring_transaction: series, starts_on: @start)
    @scenario.scenario_changes.create!(kind: "add_movement", name: "Cancelación", amount: 3_000, starts_on: @start)

    comparison = Scenario::Comparison.new(base: forecast, scenario_forecast: forecast(scenario: @scenario.reload))

    assert_equal 500, comparison.monthly_difference
    assert_equal @start >> 5, comparison.break_even_month
    first = comparison.rows.find { |row| row.month == @start }
    assert_equal(-2_500, first.total_difference)
    assert_equal 500, first.base_spending - first.spending + 3_000
  end

  test "an end date before the start is not valid" do
    change = @scenario.scenario_changes.new(kind: "add_movement", name: "X", amount: 1, starts_on: @start, ends_on: @start - 1)

    assert_not change.valid?
    assert change.errors.added?(:ends_on, :before_start)
  end

  private
    def forecast(scenario: nil)
      Forecast.new(@family, accounts: [ @account ], through: (@today >> 12).end_of_month, include_variable: false, today: @today, scenario: scenario)
    end

    def flows_named(name)
      forecast(scenario: @scenario).flows.select { |flow| flow.name == name }
    end

    def create_series(name, amount)
      @family.recurring_transactions.create!(
        account: @account, name: name, amount: amount, currency: "USD", expected_day_of_month: 15, status: "active",
        manual: true, bill_type: "bill", last_occurrence_date: @today, next_expected_date: @today
      )
    end
end
