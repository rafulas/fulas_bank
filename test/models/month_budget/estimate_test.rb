require "test_helper"

class MonthBudget::EstimateTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @user = users(:empty)
    @today = Date.new(2026, 10, 15)
    @account = Account.create!(family: @family, owner: @user, name: "BBVA", balance: 1_000,
                               currency: @family.currency, accountable: Depository.new, status: "active")
    @food = category("Comida y bebida")
    @restaurants = category("Restaurantes", parent: @food)
    @home = category("Hogar")
  end

  test "suggests the trimmed mean of the last three Octobers and the last six months" do
    spend(100, Date.new(2023, 10, 5), @food)
    spend(200, Date.new(2024, 10, 5), @food)
    spend(900, Date.new(2025, 10, 5), @food)
    [ 4, 5, 6, 7, 8 ].each { |month| spend(300, Date.new(2026, month, 10), @food) }
    spend(50, Date.new(2026, 9, 10), @food)

    # 50, 100, 200, 300 x5, 900 -> without 50 and 900: (100 + 200 + 300 x5) / 7
    assert_equal BigDecimal("257.14"), estimate.amounts[@food.id]
  end

  test "a subcategory has its own figure and also counts in its main category" do
    [ 7, 8, 9 ].each do |month|
      spend(100, Date.new(2026, month, 3), @food)
      spend(60, Date.new(2026, month, 4), @restaurants)
    end

    assert_equal BigDecimal("60"), estimate.amounts[@restaurants.id]
    assert_equal BigDecimal("160"), estimate.amounts[@food.id]
  end

  test "leaves out one-off purchases, transfers, refunds beyond spending and this month" do
    [ 7, 8, 9 ].each { |month| spend(200, Date.new(2026, month, 3), @home) }
    spend(600, Date.new(2026, 9, 20), @home, kind: "one_time")
    spend(500, Date.new(2026, 8, 20), @home, kind: "funds_movement")
    spend(999, Date.new(2026, 10, 2), @home)

    assert_equal BigDecimal("200"), estimate.amounts[@home.id]
  end

  test "suggests nothing without history" do
    assert_empty estimate.amounts
  end

  private
    def estimate
      MonthBudget::Estimate.new(@family, user: @user, month: Date.new(2026, 10, 1), today: @today)
    end

    def category(name, parent: nil)
      @family.categories.create!(name: name, parent: parent, color: "#506cd8", lucide_icon: "shapes")
    end

    def spend(amount, date, category, kind: "standard")
      create_transaction(account: @account, amount: amount, date: date, category: category, kind: kind, currency: @family.currency)
    end
end
