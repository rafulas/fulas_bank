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
end
