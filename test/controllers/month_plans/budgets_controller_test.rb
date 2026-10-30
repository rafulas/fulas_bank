require "test_helper"

class MonthPlans::BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @food = categories(:food_and_drink)
    @month = Date.current.next_month.strftime("%Y-%m")
    @first = Date.strptime(@month, "%Y-%m")
  end

  test "an amount for a category without a budget gives it one, shown in Planes" do
    get month_plan_url(month: @month)
    assert_select "a[href='#{edit_month_plan_budget_path(month: @month)}']"

    get edit_month_plan_budget_url(month: @month)
    assert_response :success
    assert_select "input[name='new_amounts[#{@food.id}]']"
    assert_select "a[href='#{new_month_plan_budget_group_path(month: @month)}']"

    patch month_plan_budget_url(month: @month), params: { new_amounts: { @food.id => "300" } }
    assert_redirected_to month_plan_url(month: @month)

    group = @family.budget_groups.find_by!(name: @food.name)
    assert_equal BigDecimal("300"), group.limit_for(@first)

    follow_redirect!
    assert_response :success
    assert_match ERB::Util.html_escape(@food.name), response.body
  end

  test "changes a budget's amount from the month on" do
    group = budget_group("Comida", @food, 300)

    get edit_month_plan_budget_url(month: @month)
    assert_select "input[name='amounts[#{group.id}]'][value='300.0']"
    assert_select "input[name='new_amounts[#{@food.id}]']", count: 0

    patch month_plan_budget_url(month: @month), params: { amounts: { group.id => "250" } }

    assert_equal BigDecimal("250"), group.reload.limit_for(@first >> 2)
  end

  test "a first budget comes filled in with what is usually spent" do
    MonthBudget::Estimate.any_instance.stubs(:amounts).returns(@food.id => BigDecimal("257.14"))

    get edit_month_plan_budget_url(month: @month)

    assert_select "input[name='new_amounts[#{@food.id}]'][value='257.14']"
    assert_match I18n.t("month_plans.budgets.edit.suggest"), response.body
  end

  test "ignores budgets and categories of another family" do
    other = Category.where.not(family_id: @family.id).first
    skip "no category of another family in the fixtures" unless other

    patch month_plan_budget_url(month: @month), params: { new_amounts: { other.id => "50" } }

    assert_redirected_to month_plan_url(month: @month)
    assert_not BudgetGroupCategory.exists?(category_id: other.id)
  end

  private
    def budget_group(name, category, amount)
      group = @family.budget_groups.create!(name: name)
      group.group_categories.create!(category: category)
      group.set_limit_from!(@first, amount)
      group
    end
end
