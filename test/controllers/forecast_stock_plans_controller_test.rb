require "test_helper"

class ForecastStockPlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "creates a plan and a year, and lists them with the estimate" do
    assert_difference -> { @user.family.stock_plans.count } => 1 do
      post forecast_stock_plans_url, params: {
        stock_plan: { name: "Bonus", investment_account_id: accounts(:investment).id, security_id: securities(:aapl).id,
                      cash_account_id: accounts(:depository).id, base_bonus: "20000", stock_percent: "28", tax_percent: "30",
                      gift_every: "10", lock_years: "3" }
      }
    end
    assert_redirected_to forecast_stock_plans_url

    plan = @user.family.stock_plans.last
    assert_equal "USD", plan.currency

    assert_difference -> { plan.grants.count } => 1 do
      post forecast_stock_plan_grants_url(plan), params: {
        stock_plan_grant: { granted_on: (Date.current + 20).iso8601, achievement_percent: "100", stock_percent: "28", shares: "", sell_on: "" }
      }
    end
    grant = plan.grants.last
    assert_nil grant.shares
    assert_equal grant.granted_on + 3.years, grant.sell_on

    get forecast_stock_plans_url
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(grant)}"

    get edit_forecast_stock_plan_grant_url(plan, grant)
    assert_response :success
  end

  test "rejects an account that is not an investment account" do
    assert_no_difference -> { StockPlan.count } do
      post forecast_stock_plans_url, params: {
        stock_plan: { name: "Bonus", investment_account_id: accounts(:depository).id, security_id: securities(:aapl).id,
                      base_bonus: "20000", stock_percent: "28", tax_percent: "30", gift_every: "10", lock_years: "3" }
      }
    end

    assert_response :unprocessable_entity
  end
end
