require "test_helper"

class Vehicle::LogbookTest < ActiveSupport::TestCase
  setup do
    @vehicle = vehicles(:one)
    @vehicle.update!(mileage_value: nil, mileage_unit: "km", fuel_type: "diesel")
  end

  test "measures consumption between full tanks, adding partial refuels to the next full one" do
    refuel(date: 30.days.ago, odometer: 10_000, quantity: 40)
    refuel(date: 20.days.ago, odometer: 10_300, quantity: 10, full_tank: false)
    refuel(date: 10.days.ago, odometer: 10_800, quantity: 30)
    refuel(date: 5.days.ago, odometer: 11_300, quantity: 25)

    series = @vehicle.logbook.consumption_series

    assert_equal [ 10_800, 11_300 ], series.map(&:odometer)
    assert_equal [ BigDecimal("5.0"), BigDecimal("5.0") ], series.map(&:per_100)
    assert_equal BigDecimal("5.0"), @vehicle.logbook.average_consumption
  end

  test "needs two full tanks before reporting consumption" do
    refuel(date: 10.days.ago, odometer: 10_000, quantity: 40)

    assert_empty @vehicle.logbook.consumption_series
    assert_nil @vehicle.logbook.average_consumption
  end

  test "cost per kilometre covers every kind of log over the distance recorded" do
    refuel(date: 30.days.ago, odometer: 10_000, quantity: 40, amount: 60)
    @vehicle.logs.create!(kind: "service", date: 20.days.ago, odometer: 10_500, amount: 140)
    @vehicle.logs.create!(kind: "expense", category: "insurance", date: 10.days.ago, amount: 300)
    refuel(date: 5.days.ago, odometer: 11_000, quantity: 50, amount: 100)

    logbook = @vehicle.logbook

    assert_equal Money.new(600, "USD"), logbook.total_spent
    assert_equal Money.new(BigDecimal("0.6"), "USD"), logbook.cost_per_km
    assert_equal 11_000, logbook.odometer
  end

  test "splits this year's spending by kind" do
    travel_to Date.new(2026, 6, 15) do
      refuel(date: Date.new(2026, 3, 1), odometer: 1_000, quantity: 40, amount: 60)
      refuel(date: Date.new(2025, 12, 1), odometer: 500, quantity: 40, amount: 55)
      @vehicle.logs.create!(kind: "expense", category: "toll", date: Date.new(2026, 4, 2), amount: 14.3)

      totals = @vehicle.logbook.year_totals

      assert_equal Money.new(60, "USD"), totals["fuel"]
      assert_equal Money.new(0, "USD"), totals["service"]
      assert_equal Money.new(BigDecimal("14.3"), "USD"), totals["expense"]
      assert_equal Money.new(BigDecimal("74.3"), "USD"), @vehicle.logbook.year_total
    end
  end

  test "flags maintenance that is overdue or due soon" do
    oil = @vehicle.maintenance_items.create!(name: "Oil", interval_km: 15_000, last_done_on: 1.year.ago.to_date, last_done_odometer: 0)
    itv = @vehicle.maintenance_items.create!(name: "ITV", interval_months: 24, last_done_on: 1.year.ago.to_date)
    @vehicle.update!(mileage_value: 14_500)

    alerts = @vehicle.logbook.maintenance_alerts.to_h

    assert alerts[oil].soon?
    assert_not alerts.key?(itv)
  end

  private
    def refuel(date:, odometer:, quantity:, amount: nil, full_tank: true)
      @vehicle.logs.create!(kind: "fuel", date: date.to_date, odometer: odometer, quantity: quantity,
                            amount: amount || quantity * 1.5, full_tank: full_tank)
    end
end
