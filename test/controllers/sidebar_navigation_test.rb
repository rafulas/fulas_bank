require "test_helper"

class SidebarNavigationTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "the sidebar has no Budgets entry and keeps Fulas Bank's order" do
    get transactions_url

    assert_response :success
    assert_select "nav a[href=?]", budgets_path, count: 0

    hrefs = css_select("nav a").map { |link| link["href"] }
    order = [ transactions_path, category_summaries_path, month_plan_path, forecast_path, subscription_costs_path, loans_overview_path, investments_overview_path, roadtrip_path ]
    positions = order.map { |path| hrefs.index(path) }

    assert positions.all?, "every entry is in the sidebar"
    assert_equal positions.sort, positions
  end
end
