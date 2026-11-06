require "test_helper"

class Transactions::PanelBalancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "the list leaves the 90-day balance to load when «Análisis» opens" do
    get transactions_url

    assert_response :success
    assert_select "turbo-frame#transactions_panel_balance[src='#{transactions_panel_balance_path}'][loading='lazy']"
    assert_select "[data-controller='time-series-chart']", count: 0
  end

  test "shows the 90-day balance of the panel's accounts" do
    get transactions_panel_balance_url

    assert_response :success
    assert_select "turbo-frame#transactions_panel_balance [data-controller='time-series-chart']"
  end
end
