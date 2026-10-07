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

  test "offers nearby bank charges of a similar amount and copies the amount when linked" do
    match = create_transaction(name: "REPSOL", date: Date.current, amount: 54.37)
    create_transaction(name: "Supermarket", date: Date.current, amount: 120)
    create_transaction(name: "Old refuel", date: 20.days.ago.to_date, amount: 54.37)

    log = @vehicle.logs.new(kind: "fuel", date: Date.current, amount: 54)

    assert_equal [ match ], log.candidate_entries

    log.assign_attributes(amount: 0, entry: match, quantity: 35)
    log.save!

    assert_equal BigDecimal("54.37"), log.amount
  end

  test "does not offer a bank charge already linked to another log" do
    charge = create_transaction(name: "REPSOL", date: Date.current, amount: 50)
    @vehicle.logs.create!(kind: "fuel", date: Date.current, amount: 50, entry: charge)

    assert_empty @vehicle.logs.new(kind: "fuel", date: Date.current, amount: 50).candidate_entries
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
