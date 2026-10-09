require "test_helper"

class Vehicles::RoadtripImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @account = accounts(:vehicle)
    @vehicle = @account.vehicle
    @vehicle.update!(license_plate: nil)
  end

  test "upload form" do
    get new_vehicle_roadtrip_import_url(@account)

    assert_response :success
    assert_select "input[type=file][name=file]"
  end

  test "shows what would be imported before saving anything" do
    assert_no_difference -> { @vehicle.logs.count } do
      post vehicle_roadtrip_import_url(@account), params: { file: fixture_file_upload("roadtrip_export.csv", "text/csv") }
    end

    assert_response :success
    assert_select "input[name=content]"
    assert_select "input[name=confirm]"
  end

  test "imports the file once confirmed" do
    content = Base64.strict_encode64(file_fixture("roadtrip_export.csv").binread)

    assert_difference -> { @vehicle.logs.count } => 8 do
      post vehicle_roadtrip_import_url(@account), params: { content: content, confirm: "1" }
    end

    assert_redirected_to account_url(@account, tab: "refuels")
    assert_equal "1234BCD", @vehicle.reload.license_plate
  end

  test "explains when the file is not a RoadTrip export" do
    post vehicle_roadtrip_import_url(@account), params: { file: fixture_file_upload("test.txt", "text/plain") }

    assert_response :unprocessable_entity
  end
end
