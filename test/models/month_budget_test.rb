require "test_helper"

class MonthBudgetTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @food = categories(:food_and_drink)
    @restaurants = categories(:subcategory)
    @other = categories(:one)
    @month = Date.current.beginning_of_month
    @next_month = @month.next_month
    # A month without fixture movements, for what is spent.
    @past = Date.new(2025, 3, 1)
  end

  test "offers the main categories, without transfers or excluded" do
    categories = budget.categories

    assert_includes categories, @food
    assert_not_includes categories, @restaurants
    assert categories.none?(&:analytics_neutral?)
  end

  test "a budget groups categories of different main ones and adds up their spending" do
    bars = @family.categories.create!(name: "Bares prueba", parent: @other, color: "#506cd8", lucide_icon: "beer")
    group = create_group("Restaurantes y bares", [ @restaurants, bars ], "300")

    create_transaction(amount: 40, category: @restaurants, date: @month + 1)
    create_transaction(amount: 25, category: bars, date: @month + 2)
    create_transaction(amount: -5, category: bars, date: @month + 3)
    create_transaction(amount: 500, category: @food, date: @month + 1)
    create_transaction(amount: 900, category: @restaurants, date: @month + 1, kind: "one_time")

    assert_equal BigDecimal("60"), budget.spent(group), "refunds take spending down; one-off purchases do not count"
    assert_equal BigDecimal("300"), group.reload.limit_for(@month)
    assert_not group.covers?(@food)
  end

  test "a main category stands for its subcategories" do
    group = create_group("Comida", [ @food ], "400", month: @past)
    create_transaction(amount: 40, category: @restaurants, date: @past + 1)

    assert group.covers?(@restaurants)
    assert_equal BigDecimal("40"), budget(@past).spent(group)
    assert_equal group, budget.group_for(@restaurants)
  end

  test "a subcategory chosen with its main category is not kept apart" do
    group = create_group("Comida", [ @food, @restaurants ], "400")

    assert_equal [ @food.id.to_s ], group.reload.chosen_ids
  end

  test "a category goes in one budget only" do
    create_group("Comida", [ @food ], "400")
    group = @family.budget_groups.new

    assert_not budget.assign(group, name: "Restaurantes", category_ids: [ @restaurants.id ], amount: "100")
    assert_match "Restaurants", group.errors.full_messages.to_sentence
    assert_not budget.assign(group, name: "Nada", category_ids: [], amount: "100")
    assert_not budget.assign(group, name: "", category_ids: [ @other.id ], amount: "100")
  end

  test "an amount holds from its month on, and earlier months keep theirs" do
    group = create_group("Comida", [ @food ], "300", month: @next_month)
    later = @next_month >> 3

    MonthBudget.new(@family, user: @user, month: later).save!(group.id => "250")
    group.reload

    assert_equal 0, group.limit_for(@month)
    assert_equal BigDecimal("300"), group.limit_for(@next_month)
    assert_equal BigDecimal("300"), group.limit_for(later.prev_month)
    assert_equal BigDecimal("250"), group.limit_for(later)
    assert_equal BigDecimal("250"), group.limit_for(later >> 12)

    MonthBudget.new(@family, user: @user, month: @next_month).save!(group.id => "350")
    assert_equal BigDecimal("350"), group.reload.limit_for(later), "from a month on replaces the later amounts"
  end

  test "a month's own amount leaves the next months as they were" do
    group = create_group("Comida", [ @food ], "300", month: @next_month)

    group.set_month_limit!(@next_month >> 2, 500)

    assert_equal BigDecimal("300"), group.limit_for(@next_month >> 1)
    assert_equal BigDecimal("500"), group.limit_for(@next_month >> 2)
    assert_equal BigDecimal("300"), group.limit_for(@next_month >> 3)
  end

  test "an amount for a category without a budget gives it one of its own" do
    budget.create_for_categories!(@food.id => "120", @other.id => "")

    group = @family.budget_groups.find_by!(name: @food.name)
    assert_equal [ @food.id.to_s ], group.chosen_ids
    assert_equal BigDecimal("120"), group.limit_for(@month)
    assert_not @family.budget_groups.exists?(name: @other.name)
  end

  test "Planes shows the budgets with an amount this month, the largest first" do
    small = create_group("Pequeño", [ @other ], "50", month: @past)
    big = create_group("Comida", [ @food ], "400", month: @past)
    create_group("Sin importe", [ @family.categories.create!(name: "Vacía prueba", color: "#000000") ], "0", month: @past)
    create_transaction(amount: 30, category: @restaurants, date: @past + 1)

    plan = MonthPlan.new(@family, user: @user, month: @past)

    assert_equal [ big, small ], plan.budget_rows.map(&:group)
    assert_equal BigDecimal("30"), plan.budget_rows.first.spent
    assert_equal big, plan.budget_row_for(@restaurants).group
    assert_equal Money.new(-420, @family.currency), Transaction::MonthSummary.new(@family, month: @past, scope: @family.transactions, user: @user).budget_difference
  end

  test "the monthly budgets kept until now become one-category budgets, month by month" do
    @family.update_column(:budget_groups_converted_at, nil)
    @family.budget_groups.destroy_all
    @family.budgets.destroy_all
    old_budget(@month, @food => 300, @other => 80)
    old_budget(@next_month, @food => 300, @restaurants => 120)

    groups = MonthBudget.new(@family.reload, user: @user, month: @month).groups.index_by(&:name)

    assert_equal [ @food.name, @other.name, @restaurants.name ].sort, groups.keys.sort
    assert_equal BigDecimal("300"), groups[@food.name].limit_for(@month)
    assert_equal 0, groups[@food.name].limit_for(@next_month), "broken down into its subcategories the next month"
    assert_equal BigDecimal("120"), groups[@restaurants.name].limit_for(@next_month >> 6)
    assert_equal 0, groups[@other.name].limit_for(@next_month)
    assert @family.reload.budget_groups_converted_at.present?

    assert_no_difference -> { BudgetGroup.count } do
      MonthBudget.new(@family, user: @user, month: @month).groups
    end
  end

  private
    def budget(month = @month)
      MonthBudget.new(@family, user: @user, month: month)
    end

    def create_group(name, categories, amount, month: @month)
      group = @family.budget_groups.new
      assert budget(month).assign(group, name: name, category_ids: categories.map(&:id), amount: amount), group.errors.full_messages.to_sentence
      group
    end

    def old_budget(month, amounts)
      record = @family.budgets.create!(start_date: month, end_date: month.end_of_month, currency: "USD",
                                       budgeted_spending: amounts.values.sum, expected_income: 0)
      amounts.each do |category, amount|
        record.budget_categories.create!(category: category, budgeted_spending: amount, currency: "USD")
      end
    end
end
