require "test_helper"

class PriceRiseDismissalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @change = recurring_transactions(:netflix_subscription).recurring_price_changes.create!(
      previous_amount: 13.99, new_amount: 15.99, effective_on: 3.days.ago.to_date, currency: "USD"
    )
  end

  test "Inicio shows the rise and dismissing hides it" do
    get root_path
    assert_select "#price-rises"

    post price_rise_dismissals_path(change_id: @change.id)
    assert_redirected_to root_path

    get root_path
    assert_select "#price-rises", count: 0
  end

  test "ignores a change that is not the family's" do
    post price_rise_dismissals_path(change_id: SecureRandom.uuid)

    assert_redirected_to root_path
    assert_empty Array(@user.reload.preferences&.dig(PriceRises::PREFERENCE_KEY))
  end
end
