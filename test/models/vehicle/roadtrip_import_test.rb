require "test_helper"

class Vehicle::RoadtripImportTest < ActiveSupport::TestCase
  setup do
    @vehicle = vehicles(:one)
    @vehicle.update!(mileage_value: nil, mileage_unit: "km", license_plate: nil)
    @content = file_fixture("roadtrip_export.csv").binread
  end

  test "reads refuels with decimal commas and partial fills" do
    refuels = import.logs.select { |log| log[:kind] == "fuel" }

    assert_equal 4, refuels.size
    assert_equal [ Date.new(2024, 1, 5), 10_000, BigDecimal("40"), BigDecimal("1.5"), BigDecimal("60"), true ],
                 refuels.first.values_at(:date, :odometer, :quantity, :unit_price, :amount, :full_tank)
    assert_equal false, refuels.second[:full_tank]
    assert_equal BigDecimal("30.5"), refuels.third[:quantity]
    assert_equal "Repsol", refuels.third[:notes]
  end

  test "files maintenance records as services or running costs" do
    others = import.logs.reject { |log| log[:kind] == "fuel" }.index_by { |log| log[:notes].lines.first.strip }

    service = others.fetch("Revisión Coche")
    assert_equal "service", service[:kind]
    assert_equal BigDecimal("429.45"), service[:amount]
    assert_equal "Revisión Coche\nCambio aceite\nCambio filtros\nTaller Pepe", service[:notes]

    assert_equal [ "expense", "road_tax" ], others.fetch("Pago IVTM 2024").values_at(:kind, :category)
    assert_equal [ "expense", "inspection" ], others.fetch("ITV 2024").values_at(:kind, :category)
    assert_equal [ "service", BigDecimal("0") ], others.fetch("Rellenar Líquido").values_at(:kind, :amount)
  end

  test "leaves out an odometer reading that cannot be right" do
    issue = import.issues.sole

    assert_equal [ Date.new(2024, 2, 20), 110_000, :jump ], [ issue.date, issue.odometer, issue.reason ]
    assert_nil import.logs.find { |log| log[:date] == Date.new(2024, 2, 20) }[:odometer]
  end

  test "imports the logs and the licence plate" do
    assert_difference -> { @vehicle.logs.count } => 8 do
      assert_equal 8, import.import!
    end

    @vehicle.reload
    assert_equal "1234BCD", @vehicle.license_plate
    assert_equal 11_100, @vehicle.mileage_value
    assert_equal 2, @vehicle.logs.expenses.count
    assert_equal BigDecimal("5.05"), @vehicle.logbook.average_consumption
  end

  test "does not import the same records twice" do
    import.import!

    second = Vehicle::RoadtripImport.new(@vehicle.reload, @content)

    assert_equal 8, second.summary.duplicates
    assert_no_difference -> { @vehicle.logs.count } do
      assert_equal 0, second.import!
    end
  end

  test "skips a refuel already typed in by hand on the same day for the same amount" do
    @vehicle.logs.create!(kind: "fuel", date: Date.new(2024, 2, 3), odometer: 11_001, quantity: 30.5, amount: 48.8)

    summary = import.summary

    assert_equal 1, summary.duplicates
    assert_equal 3, summary.counts["fuel"]
  end

  test "keeps the licence plate the vehicle already has" do
    @vehicle.update!(license_plate: "9999ZZZ")

    assert_nil import.summary.license_plate
    import.import!
    assert_equal "9999ZZZ", @vehicle.reload.license_plate
  end

  test "rejects a file that is not a RoadTrip export" do
    assert_raises(Vehicle::RoadtripImport::InvalidFile) do
      Vehicle::RoadtripImport.new(@vehicle, "Fecha;Concepto;Importe\n01/09/2026;REPSOL;-50\n").logs
    end
  end

  private
    def import
      @import ||= Vehicle::RoadtripImport.new(@vehicle, @content)
    end
end
