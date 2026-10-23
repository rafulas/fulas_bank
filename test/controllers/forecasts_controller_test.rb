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

  test "keeps the cushion and warns when the main account would drop below it" do
    get forecast_url(cushion: "999999999")

    assert_response :success
    assert_equal "999999999.0", @user.reload.preferences[Forecast::CUSHION_PREFERENCE]
    assert_select "input[name='cushion'][value='999999999']"
    warning = I18n.t("forecasts.show.cushion_breached_title", locale: @user.locale.presence || I18n.default_locale)
    assert_match ERB::Util.html_escape(warning.split(/%\{\w+\}/).max_by(&:size)), response.body

    get forecast_url(cushion: "")
    assert_nil @user.reload.preferences[Forecast::CUSHION_PREFERENCE]
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
    assert_select "table thead th", minimum: 4
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

  test "remembers the main account chosen" do
    other = @user.family.accounts.create!(name: "Ahorro", balance: 100, currency: "USD", accountable: Depository.new, owner: @user)

    get forecast_url(main_account_id: other.id)
    assert_response :success
    assert_equal other.id, @user.reload.preferences[Forecast::MAIN_ACCOUNT_PREFERENCE]

    get forecast_url
    assert_select "select[name='main_account_id'] option[selected][value='#{other.id}']"
  end

  test "«Ver cálculo» shows how the variable spending is worked out and which accounts count" do
    checking = accounts(:depository)
    category = categories(:food_and_drink)
    entry = checking.entries.create!(date: Date.current.prev_month.beginning_of_month + 4, amount: 42, currency: checking.currency,
                                     name: "Cervecería", entryable: Transaction.new(category: category))

    get variable_forecast_url(month: Date.current.next_month.beginning_of_month.iso8601), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "a[href=?]", variable_forecast_path(month: Date.current.next_month.beginning_of_month.iso8601, category: category.id)
    assert_select "input[name='counted[]'][value=?]", checking.id

    get variable_forecast_url(month: Date.current.next_month.beginning_of_month.iso8601, category: category.id), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "a[href=?]", entry_path(entry)

    patch variable_accounts_forecast_url, params: { counted: [ checking.id ] }
    assert_redirected_to forecast_url
    excluded = @user.reload.preferences[Forecast::VARIABLE_EXCLUDED_PREFERENCE]
    assert_not_includes excluded, checking.id
    assert_includes excluded, accounts(:credit_card).id
  end

  test "edits the table: hides an account's column and changes where it adds up" do
    checking = accounts(:depository)
    brokerage = accounts(:investment)

    get columns_forecast_url
    assert_response :success
    assert_select "select[name='groups[#{checking.id}]']"

    patch columns_forecast_url, params: { shown: [ checking.id ], groups: { checking.id => "cash", brokerage.id => "none" } }
    assert_redirected_to forecast_url

    preferences = @user.reload.preferences
    assert_includes preferences[Forecast::HIDDEN_COLUMNS_PREFERENCE], brokerage.id
    assert_not_includes preferences[Forecast::HIDDEN_COLUMNS_PREFERENCE], checking.id
    assert_equal "none", preferences[Forecast::COLUMN_GROUPS_PREFERENCE][brokerage.id]

    get table_forecast_url
    assert_response :success
    assert_select "th", text: I18n.t("forecasts.table.cash", locale: @user.locale.presence || I18n.default_locale)
    assert_select "th", text: brokerage.name, count: 0
  end
end
