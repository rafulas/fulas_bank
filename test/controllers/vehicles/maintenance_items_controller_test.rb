require "test_helper"

class Vehicles::MaintenanceItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @account = accounts(:vehicle)
    @vehicle = @account.vehicle
  end

  test "new form starts from a preset" do
    get new_vehicle_maintenance_item_url(@account, preset: "oil_change")

    assert_response :success
    assert_select "input[name='vehicle_maintenance_item[interval_km]'][value='15000']"
  end

  test "new item starts from the last time the logbook shows it was done" do
    @vehicle.logs.create!(kind: "service", date: Date.new(2025, 7, 8), odometer: 95_455, amount: 429.45, notes: "Cambio de aceite Y Revision")

    get new_vehicle_maintenance_item_url(@account, preset: "oil_change")

    assert_response :success
    assert_select "input[name='vehicle_maintenance_item[last_done_on]'][value='2025-07-08']"
    assert_select "input[name='vehicle_maintenance_item[last_done_odometer]'][value='95455']"
  end

  test "creates, updates and deletes an item" do
    assert_difference -> { @vehicle.maintenance_items.count } => 1 do
      post vehicle_maintenance_items_url(@account), params: {
        vehicle_maintenance_item: { name: "Tyres", interval_km: 40_000, last_done_odometer: 30_000 }
      }
    end
    assert_redirected_to account_url(@account, tab: "workshop")

    item = @vehicle.maintenance_items.last
    patch vehicle_maintenance_item_url(@account, item), params: { vehicle_maintenance_item: { interval_km: 45_000 } }
    assert_equal 45_000, item.reload.interval_km

    assert_difference -> { @vehicle.maintenance_items.count } => -1 do
      delete vehicle_maintenance_item_url(@account, item)
    end
  end

  test "rejects an item without an interval" do
    post vehicle_maintenance_items_url(@account), params: { vehicle_maintenance_item: { name: "Something" } }

    assert_response :unprocessable_entity
  end
end
