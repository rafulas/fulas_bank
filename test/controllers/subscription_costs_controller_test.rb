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
