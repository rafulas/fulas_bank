require "test_helper"

class MonthPlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "shows this month's budgets and recurring movements" do
    get month_plan_url

    assert_response :success
    assert_select "h2", text: I18n.t("month_plans.show.budgets")
    assert_select "h2", text: I18n.t("month_plans.show.recurring")
    assert_select "a[href=?]", month_plan_path(month: (Date.current.beginning_of_month << 1).strftime("%Y-%m"))
  end

  test "shows the recurring payments as a timeline" do
    get month_plan_url(view: "timeline")

    assert_response :success
    assert_select "#payments-timeline"
    assert_select "a[aria-current='true']", text: I18n.t("month_plans.show.views.timeline")
  end

  test "goes to another month, and ignores a malformed one" do
    get month_plan_url(month: "2026-03")
    assert_response :success
    assert_match I18n.l(Date.new(2026, 3, 1), format: "%B %Y"), response.body

    get month_plan_url(month: "nonsense")
    assert_response :success
  end
end
