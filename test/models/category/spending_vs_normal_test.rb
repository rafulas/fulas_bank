require "test_helper"

class Category::SpendingVsNormalTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Normal checking", balance: 0, currency: "USD", accountable: Depository.new)
    @food = @family.categories.create!(name: "Comida", color: "#22c55e")
    @leisure = @family.categories.create!(name: "Ocio", color: "#84cc16")
    @physio = @family.categories.create!(name: "Fisio", color: "#f59e0b")
  end

  test "a finished month against the average of the six before, counting months without spending" do
    (1..6).each { |back| spend(300, Date.new(2026, 10, 10) << back, @food) }
    spend(600, Date.new(2026, 7, 5), @leisure) # one month in six: 100 a month
    spend(320, Date.new(2026, 10, 3), @food)
    spend(250, Date.new(2026, 10, 4), @leisure)

    comparison = comparison(month: Date.new(2026, 10, 1), today: Date.new(2026, 11, 2))

    assert_not comparison.in_progress?
    assert_equal [ "Ocio" ], comparison.above.map(&:name)
    assert_equal 150, comparison.above.first.difference
    assert_empty comparison.below, "20 more on food is within normal"
  end

  test "a month in progress is compared with what is usually spent by this day" do
    (1..6).each { |back| spend(300, Date.new(2026, 11, 10) << back, @food) }
    spend(300, Date.new(2026, 11, 5), @food)

    comparison = comparison(month: Date.new(2026, 11, 1), today: Date.new(2026, 11, 15))
    food = comparison.rows.find { |row| row.name == "Comida" }

    assert comparison.in_progress?
    assert_equal 150, food.normal
    assert_equal [ "Comida" ], comparison.above.map(&:name)
  end

  test "a refund in the same category lowers the month's spending" do
    (1..6).each { |back| spend(100, Date.new(2026, 10, 10) << back, @physio) }
    spend(550, Date.new(2026, 10, 3), @physio)
    spend(-450, Date.new(2026, 10, 20), @physio)

    comparison = comparison(month: Date.new(2026, 10, 1), today: Date.new(2026, 11, 2))

    assert_equal 100, comparison.rows.find { |row| row.name == "Fisio" }.spent
    assert_not comparison.any?
  end

  private
    def spend(amount, date, category)
      create_transaction(account: @account, amount: amount, date: date, category: category)
    end

    def comparison(month:, today:)
      Category::SpendingVsNormal.new(@family, account_ids: [ @account.id ], month: month, today: today)
    end
end
