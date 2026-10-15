require "test_helper"

class OverviewsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
  end

  test "an investment account opens on its performance overview" do
    get account_url(accounts(:investment))

    assert_response :success
    assert_match I18n.t("investments.tabs.overview.gain_ytd"), response.body
    assert_match I18n.t("investments.tabs.overview.recent"), response.body
  end

  test "the loans page lists each loan with what is still owed" do
    get loans_overview_url

    assert_response :success
    assert_select "a[href=?]", account_path(accounts(:loan))
    assert_match accounts(:loan).name, response.body
  end

  test "the investments page lists each investment account" do
    get investments_overview_url

    assert_response :success
    assert_select "a[href=?]", account_path(accounts(:investment))
  end

  test "the forecast table opens on its own in a wide dialog" do
    get table_forecast_url(period: "1y")

    assert_response :success
    assert_select "table thead th", minimum: 4
  end
end
