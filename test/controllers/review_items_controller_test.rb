require "test_helper"

class ReviewItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @series = recurring_transactions(:netflix_subscription)
  end

  test "the bell lists what needs a look, and forgets what was seen" do
    change = @series.recurring_price_changes.create!(effective_on: 2.days.ago.to_date, previous_amount: 12.99, new_amount: 15.99, currency: "USD", source: "detected")

    get review_items_path
    assert_response :success
    assert_select "turbo-frame#review_bell li", text: /#{I18n.t("review_items.index.kinds.price_increase")}/

    post seen_review_items_path(key: "price:#{change.id}")
    assert_redirected_to root_path

    get review_items_path
    assert_select "turbo-frame#review_bell li", text: /#{I18n.t("review_items.index.kinds.price_increase")}/, count: 0
  end

  test "a malformed key is ignored" do
    post seen_review_items_path(key: "anything")

    assert_redirected_to root_path
    assert_nil @user.reload.preferences["seen_review_items"]
  end
end
