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

  test "lists every expected line by month, with a way to edit it" do
    series = @user.family.recurring_transactions.create!(
      account: accounts(:depository), name: "Seguro vida", amount: 47, currency: "USD", expected_day_of_month: 24,
      status: "active", manual: true, bill_type: "bill", last_occurrence_date: Date.current, next_expected_date: Date.current
    )

    get forecast_url(account_id: accounts(:depository).id, period: "6m")

    assert_response :success
    assert_select "details", minimum: 1
    assert_match "Seguro vida", response.body
    assert_select "a[href*='#{edit_forecast_adjustment_path}'][href*='#{CGI.escape("recurring:#{series.id}")}']", minimum: 1
  end

  test "changes, leaves out and brings back a line the app works out" do
    series = @user.family.recurring_transactions.create!(
      account: accounts(:depository), name: "Seguro vida", amount: 47, currency: "USD", expected_day_of_month: 24,
      status: "active", manual: true, bill_type: "bill", last_occurrence_date: Date.current, next_expected_date: Date.current
    )
    key = ForecastAdjustment.recurring_key(series, Date.current + 40)

    get edit_forecast_adjustment_url(key: key, date: (Date.current + 40).iso8601, amount: "47", name: "Seguro vida")
    assert_response :success
    assert_select "input[name='forecast_adjustment[name]'][value='Seguro vida']"

    patch forecast_adjustment_url, params: { forecast_adjustment: { key: key, amount: "52", name: "Seguro vida 2027", skipped: "0" } }
    assert_redirected_to forecast_url
    adjustment = @user.family.forecast_adjustments.find_by!(key: key)
    assert_equal [ BigDecimal("52"), "Seguro vida 2027", false ], [ adjustment.amount, adjustment.name, adjustment.skipped ]

    patch forecast_adjustment_url, params: { forecast_adjustment: { key: key, skipped: "1" } }
    assert adjustment.reload.skipped

    assert_difference -> { @user.family.forecast_adjustments.count } => -1 do
      delete forecast_adjustment_url(key: key)
    end
  end

  test "rejects a line of someone else's series or a malformed key" do
    other_key = "recurring:#{SecureRandom.uuid}:2026-12-01"

    assert_no_difference -> { ForecastAdjustment.count } do
      patch forecast_adjustment_url, params: { forecast_adjustment: { key: other_key, amount: "10" } }
    end

    get edit_forecast_adjustment_url(key: "recurring:../../etc")
    assert_response :not_found
  end
end
