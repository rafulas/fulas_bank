require "test_helper"

class BudgetGroup::DetailTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @restaurants = categories(:subcategory)
    @other = categories(:one)
    @month = Date.new(2025, 3, 1)
    @group = @family.budget_groups.create!(name: "Comer fuera")
    [ @restaurants, @other ].each { |category| @group.group_categories.create!(category: category) }
    @group.set_limit_from!(Date.new(2024, 12, 1), 300)
    @group.add_limit!(@month, 310)
  end

  test "the month against its amount, by category, day by day and per day" do
    create_transaction(amount: 62, category: @restaurants, date: @month + 1)
    create_transaction(amount: 31, category: @other, date: @month + 9)

    detail = detail(today: Date.new(2025, 3, 11))

    assert_equal BigDecimal("310"), detail.limit
    assert_equal BigDecimal("93"), detail.spent
    assert_equal BigDecimal("217"), detail.remaining
    assert_equal 30, detail.share
    assert_equal 21, detail.days_left
    assert_equal BigDecimal("10.33"), detail.remaining_per_day
    assert_equal BigDecimal("8.45"), detail.daily_average
    assert_equal [ @restaurants, @other ], detail.by_category.map(&:category)
    assert_equal 11, detail.pace[:spent].size
    assert_equal 62.0, detail.pace[:spent][1]
    assert_equal 2, detail.entries.size
  end

  test "the last six months with the amount each had and the average of the finished ones" do
    create_transaction(amount: 400, category: @restaurants, date: Date.new(2025, 2, 10))
    create_transaction(amount: 100, category: @restaurants, date: Date.new(2025, 1, 10))
    create_transaction(amount: 50, category: @restaurants, date: @month + 2)

    detail = detail(today: Date.new(2025, 3, 20))
    history = detail.history

    assert_equal [ @month, Date.new(2025, 2, 1), Date.new(2025, 1, 1) ], history.first(3).map(&:month)
    assert_equal [ BigDecimal("310"), BigDecimal("300"), BigDecimal("300") ], history.first(3).map(&:limit)
    assert history.second.over?
    assert_equal 0, history.last.limit, "before its first amount"
    assert_equal BigDecimal("100"), detail.history_average, "500 over the five finished months"
  end

  test "a future amount holds until the next one, and the first cannot be removed" do
    @group.add_limit!(Date.new(2025, 6, 1), 280)

    assert_equal BigDecimal("310"), @group.limit_for(Date.new(2025, 5, 1))
    assert_equal BigDecimal("280"), @group.limit_for(Date.new(2026, 1, 1))

    assert_not @group.remove_limit!(@group.limits.first)
    assert @group.remove_limit!(@group.limit_on(Date.new(2025, 6, 1)))
    assert_equal BigDecimal("310"), @group.limit_for(Date.new(2026, 1, 1))
  end

  private
    def detail(today:)
      BudgetGroup::Detail.new(@group, month_budget: MonthBudget.new(@family, user: @user, month: @month), today: today)
    end
end
