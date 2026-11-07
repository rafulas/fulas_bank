require "test_helper"

class RecapsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    Recap::Report.any_instance.stubs(:provider).returns(nil)
  end

  test "lists the running and past weeks and months" do
    get recaps_path

    assert_response :ok
    month = Recap.for(@user.family, user: @user, kind: "month", date: Date.current)
    week = Recap.for(@user.family, user: @user, kind: "week", date: Date.current)
    assert_select "a[href='#{recap_path(month)}']"
    assert_select "a[href='#{recap_path(month.previous)}']"
    assert_select "a[href='#{recap_path(week.previous)}']"
  end

  test "shows a month with its report loading apart" do
    recap = Recap.latest(@user.family, user: @user, kind: "month")

    get recap_path(recap)

    assert_response :ok
    assert_select "turbo-frame#recap_report[src='#{report_recap_path(recap)}']"
    assert_select "a[href='#{recap_path(recap.previous)}']"
  end

  test "shows a week" do
    get recap_path(Recap.latest(@user.family, user: @user, kind: "week"))

    assert_response :ok
  end

  test "renders the report" do
    recap = Recap.for(@user.family, user: @user, kind: "week", date: Date.current)

    get report_recap_path(recap)

    assert_response :ok
    assert_select "turbo-frame#recap_report h2"
  end

  test "an unknown or future period is not found" do
    get recap_path("2026-W99")
    assert_response :not_found

    get recap_path((Date.current >> 2).strftime("%Y-%m"))
    assert_response :not_found
  end
end
