require "test_helper"

class MonthBudgetTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @food = categories(:food_and_drink)
    @other = categories(:one)
    @next_month = Date.current.next_month.beginning_of_month
  end

  test "offers the main categories, without transfers or excluded" do
    categories = MonthBudget.new(@family, user: @user).categories

    assert_includes categories, @food
    assert_not_includes categories, categories(:subcategory)
    assert categories.none?(&:analytics_neutral?)
  end

  test "saving sets the month's amounts, the total and nothing on subcategories" do
    MonthBudget.new(@family, user: @user, month: @next_month).save!(@food.id => "300", @other.id => "100,5")

    budget = budget_for(@next_month)
    rows = budget.budget_categories.index_by(&:category_id)
    assert_equal BigDecimal("300"), rows[@food.id][:budgeted_spending]
    assert_equal BigDecimal("100.5"), rows[@other.id][:budgeted_spending]
    assert_equal BigDecimal("0"), rows[categories(:subcategory).id][:budgeted_spending].to_d
    assert_equal BigDecimal("400.5"), budget.budgeted_spending
  end

  test "a later month takes the latest budget before it, and a change never goes back" do
    MonthBudget.new(@family, user: @user, month: @next_month).save!(@food.id => "300")
    later = @next_month.next_month

    MonthBudget.new(@family, user: @user, month: later).ensure!
    assert_equal BigDecimal("300"), MonthBudget.new(@family, user: @user, month: later).amounts[@food.id]

    MonthBudget.new(@family, user: @user, month: later).save!(@food.id => "250")

    assert_equal BigDecimal("300"), MonthBudget.new(@family, user: @user, month: @next_month).amounts[@food.id]
    assert_equal BigDecimal("250"), MonthBudget.new(@family, user: @user, month: later).amounts[@food.id]
  end

  test "a change applies to the later months already created" do
    later = @next_month.next_month
    MonthBudget.new(@family, user: @user, month: @next_month).save!(@food.id => "300")
    MonthBudget.new(@family, user: @user, month: later).ensure!

    MonthBudget.new(@family, user: @user, month: @next_month).save!(@food.id => "350")

    assert_equal BigDecimal("350"), MonthBudget.new(@family, user: @user, month: later).amounts[@food.id]
  end

  test "Planes shows the main categories with a budget" do
    MonthBudget.new(@family, user: @user, month: @next_month).save!(@food.id => "300")

    rows = MonthPlan.new(@family, user: @user, month: @next_month).budget_rows

    assert_equal [ @food ], rows.map(&:category)
    assert_equal BigDecimal("300"), rows.first.budgeted
  end

  private
    def budget_for(month)
      @family.budgets.find_by!(start_date: month, user_id: nil)
    end
end
