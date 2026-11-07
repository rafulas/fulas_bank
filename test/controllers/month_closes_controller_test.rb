require "test_helper"

class MonthClosesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "opens the month just ended" do
    get month_closes_path

    assert_redirected_to month_close_path(MonthClose.latest(@user.family, user: @user))
  end

  test "shows the steps" do
    close = MonthClose.latest(@user.family, user: @user)

    get month_close_path(close)

    assert_response :ok
    assert_select "ol > li", count: close.steps.size
    assert_select "a[href='#{recap_path(close.recap)}']"
  end

  test "a week or a future month is not found" do
    get month_close_path(Recap.latest(@user.family, user: @user, kind: "week"))
    assert_response :not_found

    get month_close_path((Date.current >> 2).strftime("%Y-%m"))
    assert_response :not_found
  end
end
