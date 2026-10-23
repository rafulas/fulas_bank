require "test_helper"

class SubscriptionCostsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @charge = create_transaction(account: accounts(:depository), name: "SPOTIFY", amount: 10.99, date: Date.current - 2)
  end

  test "makes a subscription from a charge and shows it on the page" do
    get transaction_url(@charge)
    assert_response :success
    assert_select "form[action=?]", transaction_subscription_path(@charge)

    post transaction_subscription_url(@charge), params: { subscription: { name: "Spotify" } }
    series = @user.family.recurring_transactions.typed_subscription.find_by!(name: "Spotify")

    get subscription_costs_url
    assert_response :success
    assert_match "Spotify", response.body

    patch could_drop_subscription_cost_url(series), params: { could_drop: "1" }
    assert_includes @user.reload.preferences[SubscriptionsOverview::COULD_DROP_PREFERENCE], series.id
  end

  test "turns another recurring payment into a subscription" do
    series = recurring_transactions(:netflix_subscription)
    series.update_columns(bill_type: "bill")

    patch mark_subscription_cost_url(series)

    assert series.reload.typed_subscription?
  end

  # «Añadir suscripción» used to open the recurring form behind the preview
  # gate and did nothing. It now lets you pick a recurring payment or create one.
  test "add subscription offers the recurring payments and a blank form" do
    series = recurring_transactions(:netflix_subscription)
    series.update_columns(bill_type: "bill")
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => false))

    get pick_subscription_costs_url, headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "form[action=?]", mark_subscription_cost_path(series)
    assert_select "a[href=?]", new_recurring_transaction_path(subscription: "1")

    get new_recurring_transaction_url(subscription: "1"), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "input[name=?][value=?]", "recurring_transaction[subscription]", "1"
  end

  test "a series created from add subscription is a subscription" do
    post recurring_transactions_url, params: { recurring_transaction: {
      name: "Gimnasio", amount: 39.9, account_id: accounts(:depository).id,
      first_due_on: Date.current.iso8601, frequency_preset: "monthly", subscription: "1"
    } }

    assert @user.family.recurring_transactions.find_by!(name: "Gimnasio").typed_subscription?
  end

  test "cancels a subscription and takes it up again" do
    series = recurring_transactions(:netflix_subscription)
    series.update_columns(bill_type: "subscription")

    patch cancel_subscription_cost_url(series)
    series.reload
    assert series.paused?
    assert_equal Date.current, series.cancelled_on

    get subscription_costs_url
    assert_select "form[action=?]", resume_subscription_cost_path(series)

    patch resume_subscription_cost_url(series)
    series.reload
    assert series.active?
    assert_nil series.cancelled_on
  end

  test "insurance is not offered as a subscription" do
    insurance = recurring_transactions(:netflix_subscription)
    insurance.update_columns(bill_type: "bill", merchant_id: nil, name: "MAPFRE SEGURO COCHE", status: "active")

    get subscription_costs_url

    assert_no_match "MAPFRE SEGURO COCHE", response.body
  end

  test "only subscriptions can be cancelled from here" do
    bill = recurring_transactions(:netflix_subscription)
    bill.update_columns(bill_type: "bill")

    patch cancel_subscription_cost_url(bill)

    assert_response :not_found
    assert bill.reload.active?
  end
end
