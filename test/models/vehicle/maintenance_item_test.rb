require "test_helper"

class Vehicle::MaintenanceItemTest < ActiveSupport::TestCase
  setup do
    @vehicle = vehicles(:one)
    @vehicle.update!(mileage_unit: "km")
    @as_of = Date.new(2026, 10, 1)
  end

  test "needs a distance or time interval" do
    item = @vehicle.maintenance_items.new(name: "Oil")

    assert_not item.valid?
    assert item.errors.of_kind?(:base, :interval_required)
  end

  test "is unknown until it has been done once" do
    item = @vehicle.maintenance_items.create!(name: "Oil", interval_km: 15_000)

    assert item.status(odometer: 20_000, as_of: @as_of).unknown?
  end

  test "is overdue past its distance or its date" do
    by_distance = @vehicle.maintenance_items.create!(name: "Oil", interval_km: 15_000, last_done_odometer: 10_000, last_done_on: Date.new(2026, 1, 1))
    by_date = @vehicle.maintenance_items.create!(name: "ITV", interval_months: 12, last_done_on: Date.new(2025, 9, 1))

    status = by_distance.status(odometer: 25_500, as_of: @as_of)
    assert status.overdue?
    assert_equal(-500, status.km_left)

    status = by_date.status(odometer: 0, as_of: @as_of)
    assert status.overdue?
    assert_equal Date.new(2026, 9, 1), status.due_on
  end

  test "is due soon within a tenth of its distance or a month of its date" do
    item = @vehicle.maintenance_items.create!(name: "Oil", interval_km: 15_000, last_done_odometer: 10_000, last_done_on: Date.new(2026, 1, 1))

    assert item.status(odometer: 23_600, as_of: @as_of).soon?
    assert item.status(odometer: 20_000, as_of: @as_of).ok?
  end

  test "a recorded service moves the last done point forward" do
    item = @vehicle.maintenance_items.create!(name: "Oil", interval_km: 15_000, last_done_odometer: 10_000, last_done_on: Date.new(2025, 1, 1))
    @vehicle.logs.create!(kind: "service", maintenance_item: item, date: Date.new(2026, 5, 1), odometer: 24_000, amount: 139)

    assert_equal [ Date.new(2026, 5, 1), 24_000 ], item.last_done
    assert item.status(odometer: 25_000, as_of: @as_of).ok?
  end
end
