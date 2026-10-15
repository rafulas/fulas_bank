require "test_helper"

class MonthPlans::BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @food = categories(:food_and_drink)
    @month = Date.current.next_month.strftime("%Y-%m")
  end

  test "edits the budget from Planes and shows it there" do
    get month_plan_url(month: @month)
    assert_select "a[href='#{edit_month_plan_budget_path(month: @month)}']"

    get edit_month_plan_budget_url(month: @month)
    assert_response :success
    assert_select "input[name='amounts[#{@food.id}]']"

    patch month_plan_budget_url(month: @month), params: { amounts: { @food.id => "300" } }
    assert_redirected_to month_plan_url(month: @month)

    follow_redirect!
    assert_response :success
    assert_match ERB::Util.html_escape(@food.name), response.body
  end

  test "ignores categories of another family" do
    other = Category.where.not(family_id: @user.family_id).first
    skip "no category of another family in the fixtures" unless other

    patch month_plan_budget_url(month: @month), params: { amounts: { other.id => "50" } }

    assert_redirected_to month_plan_url(month: @month)
    assert_not BudgetCategory.where(category_id: other.id, budgeted_spending: 50).exists?
  end
end
