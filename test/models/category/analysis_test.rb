require "test_helper"

class Category::AnalysisTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Analysis checking", balance: 0, currency: "USD", accountable: Depository.new)
    @food = @family.categories.create!(name: "Comida", color: "#22c55e")
    @market = @family.categories.create!(name: "Súper", color: "#16a34a", parent: @food)
    @home = @family.categories.create!(name: "Hogar", color: "#84cc16")
    @salary = @family.categories.create!(name: "Ingresos", color: "#f59e0b")
    @today = Date.new(2026, 10, 14)
    @period = Period.custom(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31))
  end

  test "spending and income by main category, total and savings rate" do
    create_transaction(account: @account, amount: 30, date: Date.new(2026, 10, 2), category: @market)
    create_transaction(account: @account, amount: 20, date: Date.new(2026, 10, 2), category: @food)
    create_transaction(account: @account, amount: 400, date: Date.new(2026, 10, 5), category: @home)
    create_transaction(account: @account, amount: -1_000, date: Date.new(2026, 10, 1), category: @salary)
    create_transaction(account: @account, amount: 300, date: Date.new(2026, 10, 3), kind: "funds_movement")

    assert_equal [ [ "Hogar", 400 ], [ "Comida", 50 ] ], analysis.spending_slices.map { |slice| [ slice.name, slice.amount.to_i ] }
    assert_equal [ [ "Ingresos", 1_000 ] ], analysis.income_slices.map { |slice| [ slice.name, slice.amount.to_i ] }
    assert_equal Money.new(550, "USD"), analysis.net
    assert_equal 55, analysis.savings_rate
  end

  test "the month's calendar, each day with what it went on" do
    create_transaction(account: @account, amount: 30, date: Date.new(2026, 10, 9), category: @market)
    create_transaction(account: @account, amount: 10, date: Date.new(2026, 10, 9), category: @home)
    create_transaction(account: @account, amount: 99, date: Date.new(2026, 10, 20), category: @home)

    days = analysis.calendar_days
    ninth = days.find { |day| day.date == Date.new(2026, 10, 9) }

    assert_equal 31, days.size
    assert_equal(-40, ninth.total.to_i)
    assert_equal [ "Comida", "Hogar" ], ninth.slices.map(&:name)
    assert_empty days.find { |day| day.date == Date.new(2026, 10, 20) }.slices, "days after today stay empty"
  end

  test "tags and merchants with the most spending" do
    tag = @family.tags.create!(name: "Cupra", color: "#f97316")
    entry = create_transaction(account: @account, name: "Gasolinera", amount: 60, date: Date.new(2026, 10, 3), category: @home)
    entry.transaction.update!(tags: [ tag ])
    create_transaction(account: @account, name: "Mercadona", amount: 25, date: Date.new(2026, 10, 4), category: @market)
    create_transaction(account: @account, name: "Mercadona", amount: 15, date: Date.new(2026, 10, 6), category: @market)

    assert_equal [ [ tag, 60 ] ], analysis.tag_totals.map { |found, amount| [ found, amount.to_i ] }
    assert_equal [ [ "Gasolinera", 60 ], [ "Mercadona", 40 ] ], analysis.merchant_totals.map { |name, amount| [ name, amount.to_i ] }
  end

  test "the last six months, income up and spending down, and their average" do
    create_transaction(account: @account, amount: -2_000, date: Date.new(2026, 5, 28), category: @salary)
    create_transaction(account: @account, amount: 500, date: Date.new(2026, 5, 3), category: @home)
    create_transaction(account: @account, amount: 100, date: Date.new(2026, 10, 3), category: @market)

    bars = analysis.month_bars

    assert_equal (5..10).map { |month| Date.new(2026, month, 1) }, bars.map(&:month)
    assert_equal [ 2_000, 500 ], [ bars.first.income.sum(&:amount).to_i, bars.first.spending.sum(&:amount).to_i ]
    assert_equal [ "Comida" ], bars.last.spending.map(&:name)
    assert_equal Money.new((2_000 - 500 - 100) / 6.0, "USD").amount.round(2), analysis.month_bars_average.amount.round(2)
  end

  test "average daily spending over the days elapsed" do
    create_transaction(account: @account, amount: 140, date: Date.new(2026, 10, 2), category: @home)

    assert_equal 14, analysis.days_elapsed
    assert_equal Money.new(10, "USD"), analysis.daily_average
  end

  private
    def analysis
      Category::Analysis.new(@family, period: @period, account_ids: [ @account.id ], today: @today)
    end
end
