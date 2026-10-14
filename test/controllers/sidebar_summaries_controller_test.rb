require "test_helper"

class SidebarSummariesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "the left panel's summary comes in its own frame" do
    get sidebar_summary_url, headers: { "Turbo-Frame" => "sidebar-summary" }

    assert_response :success
    assert_select "turbo-frame#sidebar-summary #sidebar-summary"
  end
end
