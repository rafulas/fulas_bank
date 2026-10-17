require "test_helper"

# Fulas Bank: the «Volver» button in the top bar, for the Mac app, which has
# no browser back button.
class HistoryBackButtonTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "a vehicle page offers going back, falling back to RoadTrip" do
    get account_path(accounts(:vehicle))
    assert_response :ok

    assert_select "[data-controller='history-back'][data-history-back-fallback-value=?]", roadtrip_path
  end

  test "Inicio has nowhere to go back to" do
    get root_path
    assert_response :ok

    assert_select "[data-controller='history-back']", count: 0
  end
end
