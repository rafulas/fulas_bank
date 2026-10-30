require "test_helper"

class MonthPlans::BudgetGroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @food = categories(:food_and_drink)
    @restaurants = categories(:subcategory)
    @other = categories(:one)
    @month = Date.current.strftime("%Y-%m")
    @first = Date.current.beginning_of_month
  end

  test "creates a budget that groups categories of different main ones" do
    get new_month_plan_budget_group_url(month: @month)
    assert_response :success
    assert_select "input[type=checkbox][name='budget_group[category_ids][]'][value='#{@restaurants.id}']"

    assert_difference -> { @family.budget_groups.count }, 1 do
      post month_plan_budget_groups_url(month: @month),
           params: { budget_group: { name: "Restaurantes y otros", amount: "180", category_ids: [ @restaurants.id, @other.id ] } }
    end
    assert_redirected_to month_plan_url(month: @month)

    group = @family.budget_groups.find_by!(name: "Restaurantes y otros")
    assert_equal [ @other.id, @restaurants.id ].map(&:to_s).sort, group.chosen_ids.sort
    assert_equal BigDecimal("180"), group.limit_for(@first)

    follow_redirect!
    assert_match "Restaurantes y otros", response.body
  end

  test "refuses a category already in another budget" do
    post month_plan_budget_groups_url(month: @month), params: { budget_group: { name: "Comida", amount: "400", category_ids: [ @food.id ] } }

    get new_month_plan_budget_group_url(month: @month)
    assert_select "input[value='#{@restaurants.id}'][disabled]"

    assert_no_difference -> { @family.budget_groups.count } do
      post month_plan_budget_groups_url(month: @month),
           params: { budget_group: { name: "Restaurantes", amount: "100", category_ids: [ @restaurants.id ] } }
    end
    assert_response :unprocessable_entity
  end

  test "edits the name, categories and amount, and deletes it" do
    post month_plan_budget_groups_url(month: @month), params: { budget_group: { name: "Comida", amount: "400", category_ids: [ @food.id ] } }
    group = @family.budget_groups.find_by!(name: "Comida")

    get edit_month_plan_budget_group_url(group, month: @month)
    assert_response :success
    assert_select "input[name='budget_group[name]'][value='Comida']"

    patch month_plan_budget_group_url(group, month: @month),
          params: { budget_group: { name: "Comida y más", amount: "450", category_ids: [ @food.id, @other.id ] } }
    assert_redirected_to month_plan_url(month: @month)

    group.reload
    assert_equal "Comida y más", group.name
    assert_equal 2, group.chosen_ids.size
    assert_equal BigDecimal("450"), group.limit_for(@first)

    delete month_plan_budget_group_url(group, month: @month)
    assert_redirected_to month_plan_url(month: @month)
    assert_not BudgetGroup.exists?(group.id)
  end

  test "shows the budget on its own and sets future amounts" do
    post month_plan_budget_groups_url(month: @month), params: { budget_group: { name: "Comida", amount: "400", category_ids: [ @food.id ] } }
    group = @family.budget_groups.find_by!(name: "Comida")

    get month_plan_url(month: @month)
    assert_select "a[href='#{month_plan_budget_group_path(group, month: @month)}']"

    get month_plan_budget_group_url(group, month: @month)
    assert_response :success
    assert_match I18n.t("month_plans.budget_groups.show.history"), response.body

    future = (@first >> 2).strftime("%Y-%m")
    post month_plan_budget_group_limits_url(group, month: @month), params: { limit_month: future, amount: "350" }
    assert_redirected_to month_plan_budget_group_url(group, month: @month)
    assert_equal BigDecimal("350"), group.reload.limit_for(@first >> 5)
    assert_equal BigDecimal("400"), group.limit_for(@first >> 1)

    delete month_plan_budget_group_limit_url(group, group.limit_on(@first >> 2), month: @month)
    assert_equal BigDecimal("400"), group.reload.limit_for(@first >> 5)
  end
end
