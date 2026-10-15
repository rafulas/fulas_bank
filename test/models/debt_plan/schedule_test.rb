require "test_helper"

class DebtPlan::ScheduleTest < ActiveSupport::TestCase
  Loan = DebtPlan::Schedule::Loan

  setup do
    @loans = [
      Loan.new(key: "car", name: "Coche", balance: 8_000.to_d, rate: 8.to_d, payment: 200.to_d, order: 3),
      Loan.new(key: "home", name: "Hipoteca", balance: 100_000.to_d, rate: 2.to_d, payment: 600.to_d, order: 1),
      Loan.new(key: "free", name: "Sin intereses", balance: 3_000.to_d, rate: 0.to_d, payment: 300.to_d, order: 2)
    ]
    @start = Date.new(2026, 11, 1)
  end

  test "orders the loans by strategy" do
    order = ->(strategy) { DebtPlan::Schedule.new(loans: @loans, strategy: strategy, start: @start).ordered_loans.map(&:key) }

    assert_equal %w[car home free], order.call("avalanche")
    assert_equal %w[free car home], order.call("snowball")
    assert_equal %w[free car home], order.call("stair_stepper")
    assert_equal %w[car home free], order.call("table_order")
    assert_equal %w[car free home], order.call("custom_highest")
    assert_equal %w[home free car], order.call("custom_lowest")
  end

  test "each month accrues interest and pays the usual payments" do
    schedule = DebtPlan::Schedule.new(loans: @loans, strategy: "no_snowball", start: @start)
    first = schedule.months.first

    assert_equal @start, first.date
    assert_equal BigDecimal("53.33"), first.interest["car"]
    assert_equal BigDecimal("0"), first.interest["free"]
    assert_equal BigDecimal("1100"), first.total_payment
    assert_equal BigDecimal("2700"), first.balances["free"]
  end

  test "the snowball passes a finished loan's payment to the next one" do
    without = DebtPlan::Schedule.new(loans: @loans, strategy: "no_snowball", start: @start)
    with = DebtPlan::Schedule.new(loans: @loans, strategy: "snowball", start: @start)

    # The interest-free loan ends after ten payments; from then on its 300
    # go to the car.
    assert_equal 10, with.results.find { |result| result.loan.key == "free" }.months_to_pay_off
    assert_equal BigDecimal("300"), with.months[10].snowball
    assert_equal BigDecimal("0"), without.months[10].snowball
    assert with.months.size < without.months.size
    assert with.total_interest < without.total_interest
    assert with.paid_off?
  end

  test "one-off contributions go to the first loan of the strategy that month" do
    schedule = DebtPlan::Schedule.new(loans: @loans, strategy: "avalanche", start: @start,
                                      extra_payments: { Date.new(2027, 3, 15) => 5_000 })
    march = schedule.months.find { |month| month.date == Date.new(2027, 3, 1) }

    assert_equal BigDecimal("5000"), march.additional_total
    assert_equal({ "car" => BigDecimal("5000") }, march.additional)
    assert_equal BigDecimal("5200"), march.payments["car"]
  end

  test "a contribution larger than a loan moves on to the next" do
    schedule = DebtPlan::Schedule.new(loans: @loans, strategy: "snowball", start: @start,
                                      extra_payments: { @start => 5_000 })
    first = schedule.months.first

    assert_equal BigDecimal("0"), first.balances["free"]
    assert_equal BigDecimal("2700"), first.additional["free"]
    assert_equal BigDecimal("2300"), first.additional["car"]
  end

  test "a loan with no payment and no extra is never paid off" do
    loans = [ Loan.new(key: "x", name: "X", balance: 100.to_d, rate: 0.to_d, payment: 0.to_d, order: nil) ]
    schedule = DebtPlan::Schedule.new(loans: loans, strategy: "avalanche", start: @start)

    assert_not schedule.paid_off?
    assert_nil schedule.payoff_date
    assert_nil schedule.results.first.months_to_pay_off
  end

  test "tells which loan is cleared first, and when" do
    schedule = DebtPlan::Schedule.new(loans: @loans, strategy: "snowball", start: @start)

    first = schedule.first_paid_off

    assert_equal "free", first.loan.key
    assert_equal schedule.results.find { |result| result.loan.key == "free" }.paid_off_on, first.paid_off_on
  end

  test "warns of a loan whose interest is at least its payment" do
    loans = @loans + [ Loan.new(key: "card", name: "Tarjeta revolving", balance: 6_000.to_d, rate: 24.to_d, payment: 100.to_d, order: nil) ]

    growing = DebtPlan::Schedule.new(loans: loans, strategy: "avalanche", start: @start).growing_loans

    # 6.000 € at 24 % is 120 € of interest a month, more than its 100 €.
    assert_equal [ "card" ], growing.map(&:key)
  end
end
