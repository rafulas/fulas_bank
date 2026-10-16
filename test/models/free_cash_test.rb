require "test_helper"

class FreeCashTest < ActiveSupport::TestCase
  setup do
    @period = Period.custom(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31))
    @today = Date.new(2026, 10, 16)
  end

  test "what is left, the days to go and what can still be spent a day" do
    free_cash = build(income: 2_000, expense: 800)

    assert_equal Money.new(1_200, "EUR"), free_cash.free
    assert_equal 16, free_cash.days_left
    assert_equal Money.new(50, "EUR"), free_cash.daily_average
    assert_equal Money.new(75, "EUR"), free_cash.per_day_left
  end

  test "saving rate against the 20 % guideline" do
    assert_equal 60.0, build(income: 2_000, expense: 800).saving_rate
    assert build(income: 2_000, expense: 800).meets_target?
    assert_not build(income: 2_000, expense: 1_900).meets_target?
    assert_nil build(income: 0, expense: 100).saving_rate
  end

  test "spending against the same point of the period before" do
    assert_equal 25, build(income: 2_000, expense: 800, previous: 640).expense_change
    assert_equal(-20, build(income: 2_000, expense: 800, previous: 1_000).expense_change)
    assert_nil build(income: 2_000, expense: 800, previous: 0).expense_change
    assert_nil build(income: 2_000, expense: 800).expense_change
  end

  test "the comparison covers the same days of the period before" do
    comparison = FreeCash.comparison_period(@period, today: @today)

    assert_equal Date.new(2026, 8, 31), comparison.start_date
    assert_equal Date.new(2026, 9, 15), comparison.end_date
  end

  test "a closed period has no days left nor a daily allowance" do
    free_cash = build(income: 2_000, expense: 800, today: Date.new(2026, 11, 5))

    assert_nil free_cash.days_left
    assert_nil free_cash.per_day_left
    assert_equal Money.new(800.to_d / 31, "EUR"), free_cash.daily_average
  end

  private
    def build(income:, expense:, previous: nil, today: @today)
      FreeCash.new(
        income: Money.new(income, "EUR"),
        expense: Money.new(expense, "EUR"),
        period: @period,
        previous_expense: previous && Money.new(previous, "EUR"),
        today: today
      )
    end
end
