require "test_helper"

class Vehicle::LogTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @vehicle = vehicles(:one)
    @vehicle.update!(mileage_value: 1_000, mileage_unit: "km")
  end

  test "works out the missing refuel figure from the other two" do
    from_price = @vehicle.logs.create!(kind: "fuel", date: Date.current, quantity: 40, unit_price: BigDecimal("1.5"))
    from_total = @vehicle.logs.create!(kind: "fuel", date: Date.current, amount: 60, unit_price: BigDecimal("1.5"))
    from_quantity = @vehicle.logs.create!(kind: "fuel", date: Date.current, amount: 60, quantity: 40)

    assert_equal BigDecimal("60"), from_price.amount
    assert_equal BigDecimal("40"), from_total.quantity
    assert_equal BigDecimal("1.5"), from_quantity.unit_price
  end

  test "takes the vehicle account's currency" do
    log = @vehicle.logs.create!(kind: "expense", category: "parking", date: Date.current, amount: 9.5)

    assert_equal accounts(:vehicle).currency, log.currency
  end

  test "moves the vehicle's mileage forward but never back" do
    @vehicle.logs.create!(kind: "fuel", date: Date.current, odometer: 1_500, quantity: 30, amount: 45)
    assert_equal 1_500, @vehicle.reload.mileage_value

    @vehicle.logs.create!(kind: "fuel", date: 1.month.ago.to_date, odometer: 900, quantity: 30, amount: 45)
    assert_equal 1_500, @vehicle.reload.mileage_value
  end

  test "requires a category for other expenses" do
    log = @vehicle.logs.new(kind: "expense", date: Date.current, amount: 10)

    assert_not log.valid?
    assert log.errors.of_kind?(:category, :inclusion)
  end

  test "offers nearby bank charges, closest amount first, and copies the amount when linked" do
    supermarket = create_transaction(name: "Supermarket", date: Date.current, amount: 120)
    match = create_transaction(name: "REPSOL", date: 3.days.ago.to_date, amount: 54.37)
    old = create_transaction(name: "Old refuel", date: 20.days.ago.to_date, amount: 54.37)
    refund = create_transaction(name: "Refund", date: Date.current, amount: -54)

    log = @vehicle.logs.new(kind: "fuel", date: Date.current, amount: 54)
    candidates = log.candidate_entries

    assert_equal match, candidates.first
    assert_not_includes candidates, supermarket, "a refuel is only offered petrol stations"
    assert_not_includes candidates, old
    assert_not_includes candidates, refund
    assert_not_includes candidates, entries(:transfer_out), "paying off the card is not a vehicle cost"

    log.assign_attributes(amount: 0, entry: match, quantity: 35)
    log.save!

    assert_equal BigDecimal("54.37"), log.amount
  end

  test "offers only charges that look like a vehicle cost, the likeliest first and the rest by date" do
    family = accounts(:vehicle).family
    fuel = family.categories.create!(name: "Combustible", color: "#506cd8")
    groceries = family.categories.create!(name: "Supermercado", color: "#68b448")
    other_car = family.accounts.create!(name: "BMW NineT", balance: 0, currency: "USD", accountable: Vehicle.new)
    bmw_tag = family.tags.create!(name: "BMW NineT")

    repsol = create_transaction(name: "Repsol", date: 5.days.ago.to_date, amount: 70, category: fuel)
    shell = create_transaction(name: "Shell", date: 1.day.ago.to_date, amount: 40, category: fuel)
    cepsa = create_transaction(name: "Cepsa", date: 8.days.ago.to_date, amount: 30, category: fuel)
    uncategorized = create_transaction(name: "Sin categoría", date: 3.days.ago.to_date, amount: 20)
    supermarket = create_transaction(name: "Ahorramas", date: 2.days.ago.to_date, amount: 69, category: groceries)
    for_the_bmw = create_transaction(name: "Repsol moto", date: 2.days.ago.to_date, amount: 70, category: fuel, tags: [ bmw_tag ])

    candidates = @vehicle.logs.new(kind: "fuel", date: 5.days.ago.to_date, amount: 70).candidate_entries

    assert_equal [ repsol, shell, cepsa ], candidates
    assert_not_includes candidates, uncategorized, "with no category, only a petrol station's name counts"
    assert_not_includes candidates, supermarket
    assert_not_includes candidates, for_the_bmw, "a charge tagged with the other vehicle is that one's"
    assert_includes other_car.vehicle.logs.new(kind: "fuel", date: 2.days.ago.to_date, amount: 70).candidate_entries, for_the_bmw
  end

  test "a refuel is offered uncategorized petrol stations; a workshop log keeps every vehicle cost" do
    family = accounts(:vehicle).family
    parking = family.categories.find_by(name: "Aparcamiento") || family.categories.create!(name: "Aparcamiento", color: "#506cd8")

    station = create_transaction(name: "E.S. Pozuelo", date: 2.days.ago.to_date, amount: 40)
    waylet = create_transaction(name: "Waylet Madrid", date: 3.days.ago.to_date, amount: 41)
    beach = create_transaction(name: "Compra La Manga", date: 1.day.ago.to_date, amount: 28)
    car_park = create_transaction(name: "Telpark", date: 1.day.ago.to_date, amount: 3, category: parking)

    refuel = @vehicle.logs.new(kind: "fuel", date: Date.current, amount: 40).candidate_entries
    assert_includes refuel, station
    assert_includes refuel, waylet
    assert_not_includes refuel, beach
    assert_not_includes refuel, car_park

    expense = @vehicle.logs.new(kind: "expense", category: "parking", date: Date.current, amount: 3).candidate_entries
    assert_includes expense, car_park
    assert_includes expense, beach, "other costs keep the uncategorized charges"
  end

  test "does not offer a bank charge already linked to another log" do
    charge = create_transaction(name: "REPSOL", date: Date.current, amount: 50)
    @vehicle.logs.create!(kind: "fuel", date: Date.current, amount: 50, entry: charge)

    assert_not_includes @vehicle.logs.new(kind: "fuel", date: Date.current, amount: 50).candidate_entries, charge
  end

  test "rejects a bank charge from another family" do
    other_account = families(:empty).accounts.create!(
      name: "Other family checking", balance: 0, currency: "USD", accountable: Depository.new
    )
    other_charge = create_transaction(account: other_account, name: "REPSOL", amount: 10)

    log = @vehicle.logs.new(kind: "fuel", date: Date.current, amount: 10, entry: other_charge)

    assert_not log.valid?
    assert log.errors.of_kind?(:entry, :invalid)
  end
end
