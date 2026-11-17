require "test_helper"

class MerchantActivitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @entry = entries(:transaction)
  end

  test "lists the merchants and opens one" do
    get merchant_activities_url(period: "last_365_days")
    assert_response :success

    get merchant_activities_url(period: "last_365_days", search: @entry.name.first(4))
    assert_response :success

    name = @entry.transaction.merchant&.name || @entry.name
    get merchant_activity_url(name: name, period: "last_365_days")
    assert_response :success
    assert_select "h1", text: name
  end

  test "an unknown merchant is not found" do
    get merchant_activity_url(name: "No existe en ninguna parte")
    assert_response :not_found
  end
end
