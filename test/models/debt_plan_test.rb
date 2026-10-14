require "test_helper"

class DebtPlanTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @user = users(:empty)
    @plan = @family.create_debt_plan!
    @loan = @family.accounts.create!(name: "Coche", balance: 6_000, currency: "USD",
                                     accountable: Loan.new(interest_rate: 6, payment_amount: 250, payment_day: 10))
  end

  test "uses the loan's payment unless the plan has its own" do
    assert_equal BigDecimal("250"), @plan.payment_for(@loan)

    @plan.assign_loan_settings([ @loan ], { @loan.id => { "payment" => "400", "order" => "2" } })

    assert_equal BigDecimal("400"), @plan.payment_for(@loan)
    assert_equal 2, @plan.order_for(@loan)
  end

  test "keeps only the family's recurring movements and real exclusions" do
    foreign = RecurringTransaction.where.not(family_id: @family.id).first
    @plan.assign_loan_settings([ @loan ], { @loan.id => { "recurring_transaction_id" => foreign&.id || SecureRandom.uuid, "excluded" => "0" } })

    assert_equal({}, @plan.loan_settings)
  end

  test "repeats a yearly contribution every year up to its end" do
    @plan.extra_payments.create!(date: Date.new(2027, 3, 15), amount: 15_000, repeats_until: Date.new(2028, 12, 31), name: "Bonus")
    @plan.extra_payments.create!(date: Date.new(2027, 3, 1), amount: 500)

    totals = @plan.extra_payments_by_month(Date.new(2026, 10, 14))

    assert_equal({ Date.new(2027, 3, 1) => BigDecimal("15500"), Date.new(2028, 3, 1) => BigDecimal("15000") }, totals)
  end

  test "the schedule starts next month with the loans not left out" do
    @family.accounts.create!(name: "Fuera", balance: 1_000, currency: "USD", accountable: Loan.new(interest_rate: 0, payment_amount: 100)).tap do |other|
      @plan.update!(loan_settings: { other.id => { "excluded" => "1" } })
    end

    schedule = @plan.schedule(@user, today: Date.new(2026, 10, 14))

    assert_equal Date.new(2026, 11, 1), schedule.start
    assert_equal [ "Coche" ], schedule.loans.map(&:name)
  end

  test "feeds the forecast with the payments on the loan's day and the contributions on their date" do
    @plan.update!(feeds_forecast: true)
    @plan.extra_payments.create!(date: Date.new(2026, 12, 20), amount: 1_000, name: "Bonus")

    feed = @plan.forecast_feed(@user, today: Date.new(2026, 10, 14))

    assert_equal [ Date.new(2026, 11, 10), "Coche", BigDecimal("250") ], feed.payments.first
    assert_equal [ [ Date.new(2026, 12, 20), "Bonus", BigDecimal("1000") ] ], feed.contributions
    assert_nil @plan.tap { |plan| plan.feeds_forecast = false }.forecast_feed(@user)
  end
end
