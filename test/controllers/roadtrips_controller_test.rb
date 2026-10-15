require "test_helper"

class RoadtripsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "lists the cars and motorbikes, linked from the sidebar" do
    get roadtrip_url

    assert_response :success
    assert_select "a[href='#{roadtrip_path}']"
    assert_select "##{ActionView::RecordIdentifier.dom_id(accounts(:vehicle), :roadtrip)}[href='#{account_path(accounts(:vehicle))}']"
  end
end
