require "test_helper"

class ForecastsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "shows the forecast for the default period" do
    get forecast_url

    assert_response :success
    assert_select "#forecast-chart[data-controller='time-series-chart']"
  end

  test "shows one account up to a typed date, without the variable spending" do
    get forecast_url(account_id: accounts(:depository).id, until: (Date.current + 2.years).iso8601, variable: "0")

    assert_response :success
    assert_select "option[value='#{accounts(:depository).id}'][selected]"
  end

  test "adds, edits and deletes an expected one-off movement" do
    assert_difference -> { @user.family.forecast_items.count } => 1 do
      post forecast_items_url, params: {
        forecast_item: { name: "Devolución renta", nature: "inflow", amount: "450", date: (Date.current + 20).iso8601, account_id: accounts(:depository).id }
      }
    end
    assert_redirected_to forecast_url

    item = @user.family.forecast_items.last
    assert_equal "USD", item.currency

    patch forecast_item_url(item), params: { forecast_item: { amount: "500" } }
    assert_equal BigDecimal("500"), item.reload.amount

    assert_difference -> { @user.family.forecast_items.count } => -1 do
      delete forecast_item_url(item)
    end
  end

  test "rejects an account outside the forecast" do
    assert_no_difference -> { ForecastItem.count } do
      post forecast_items_url, params: {
        forecast_item: { name: "Coche", nature: "outflow", amount: "100", date: (Date.current + 5).iso8601, account_id: accounts(:vehicle).id }
      }
    end

    assert_response :unprocessable_entity
  end
end
