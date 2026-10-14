require "test_helper"

class MonthPlanTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @user = users(:empty)
    @account = @family.accounts.create!(name: "Plan checking", balance: 3_000, currency: "USD", accountable: Depository.new)
    @today = Date.new(2026, 10, 14)
  end

  test "this month's payments, paid and pending, grouped by kind" do
    rent = series("Alquiler", 900, day: 1, bill_type: "bill")
    netflix = series("Netflix", 15, day: 20, bill_type: "subscription")
    salary = series("Nómina", -2_500, day: 28, bill_type: "income")

    occurrence(rent, Date.new(2026, 10, 1)).tap do |paid|
      paid.allocations.create!(allocated_amount: 900, currency: "USD", source: "user_created")
      paid.close!("paid", source: "user")
    end
    occurrence(netflix, Date.new(2026, 10, 20))
    occurrence(salary, Date.new(2026, 10, 28))

    assert_equal %w[Alquiler Netflix Nómina], plan.payments.map(&:name)
    assert_equal [ :paid, :expected, :expected ], plan.payments.map(&:state)
    assert_equal %w[bills subscriptions income], plan.groups.map(&:key)
    assert_equal Money.new(900, "USD"), plan.paid_total
    assert_equal Money.new(15, "USD"), plan.pending_total
    assert_equal 98, plan.paid_share
    assert_equal Money.new(3_000 + 2_500 - 15, "USD"), plan.balance_after_recurring
  end

  test "a payment whose date passed unpaid is overdue" do
    gym = series("Gimnasio", 40, day: 5, bill_type: "bill")
    occurrence(gym, Date.new(2026, 10, 5))

    assert_equal :overdue, plan.payments.first.state
  end

  test "recurring movements coming after this month" do
    series("Seguro coche", 300, day: 22, bill_type: "bill", anchor: Date.new(2026, 12, 22), yearly: true)

    upcoming = plan.upcoming

    assert_equal [ "Seguro coche" ], upcoming.map { |item| item.series.display_name }
    assert_operator upcoming.first.date, :>, Date.new(2026, 10, 31)
  end

  test "spending ahead of the month's pace shows in red" do
    row = MonthPlan::BudgetRow.new(category: @family.categories.new(name: "Gasolina"), budgeted: 300, spent: 177)

    assert plan.ahead_of_pace?(row), "59% spent with 45% of the month gone"
    assert_not plan.ahead_of_pace?(row.with(spent: 100))
    assert plan.ahead_of_pace?(row.with(spent: 400))
  end

  test "no budget, no budget rows" do
    assert_nil plan.budget
    assert_empty plan.budget_rows
  end

  private
    def plan
      MonthPlan.new(@family, user: @user, month: @today, today: @today)
    end

    def series(name, amount, day:, bill_type:, anchor: nil, yearly: false)
      record = @family.recurring_transactions.create!(
        account: @account, name: name, amount: amount, currency: "USD", expected_day_of_month: day,
        status: "active", manual: true, bill_type: bill_type, dedup_scope: name,
        last_occurrence_date: anchor || Date.new(2026, 9, day), next_expected_date: anchor || Date.new(2026, 10, day),
        anchor_date: anchor
      )
      record.recurrence_rules.create!(frequency: "yearly", interval: 1, day_of_month: day, month_of_year: anchor.month) if yearly
      record.recurring_occurrences.where(due_on: Date.new(2026, 10, 1)..Date.new(2026, 10, 31)).delete_all
      record.reload
    end

    def occurrence(series, date)
      series.recurring_occurrences.create!(family: @family, original_due_on: date, due_on: date, currency: "USD")
    end
end
