require "test_helper"

class AssetLinkerTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @vehicle = vehicles(:one)
    @property = properties(:one)
    @fuel = category("Combustible")
    @home_insurance = category("Seguro de hogar")
    @linker = AssetLinker.new(@family)
  end

  test "creates a pending refuel from a fuel charge, kept out of the logbook until confirmed" do
    charge = create_transaction(name: "REPSOL", amount: 62.5, date: 2.days.ago.to_date, category: @fuel)

    assert_equal 1, @linker.run!

    log = @vehicle.logs.find_by!(entry: charge)
    assert_equal "fuel", log.kind
    assert_equal "new", log.suggestion
    assert_equal BigDecimal("62.5"), log.amount
    assert_empty @vehicle.logbook.logs

    log.confirm_link!
    assert_includes @vehicle.reload.logbook.logs, log
  end

  test "links a refuel the user already typed, even when the amount paid differs" do
    log = @vehicle.logs.create!(kind: "fuel", date: 1.day.ago.to_date, odometer: 10_000, quantity: 40, amount: 70)
    charge = create_transaction(name: "REPSOL", amount: 65.3, date: Date.current, category: @fuel)

    @linker.run!

    log.reload
    assert_equal charge, log.entry
    assert_equal "link", log.suggestion
    assert_equal BigDecimal("70"), log.amount, "the fuel figure is the user's, not the bank's"
    assert_equal 1, @vehicle.logs.count
  end

  test "a tag naming the property sends the charge there, with its category's kind" do
    tag = @family.tags.create!(name: "Casa")
    charge = create_transaction(name: "MAPFRE HOGAR", amount: 320, category: @home_insurance, tags: [ tag ])

    @linker.run!

    expense = @property.expenses.find_by!(entry: charge)
    assert_equal "insurance", expense.kind
    assert expense.pending?
  end

  test "general categories need the tag" do
    taxes = category("Impuestos")
    untagged = create_transaction(name: "AYUNTAMIENTO", amount: 400, category: taxes)
    tagged = create_transaction(name: "AYUNTAMIENTO IBI", amount: 410, category: taxes, tags: [ @family.tags.create!(name: "Vivienda") ])

    @linker.run!

    assert_nil AssetLink.for_entry(untagged)
    assert_equal "tax", AssetLink.for_entry(tagged).kind
  end

  test "a rejected charge is not proposed again for that account" do
    charge = create_transaction(name: "REPSOL", amount: 50, category: @fuel)
    @linker.run!

    @vehicle.logs.find_by!(entry: charge).reject_link!

    assert_not @vehicle.logs.exists?(entry_id: charge.id)
    assert_equal 0, AssetLinker.new(@family).run!
    assert_not @vehicle.logs.exists?(entry_id: charge.id)
  end

  test "rejecting a matched link keeps the user's record without the charge" do
    log = @vehicle.logs.create!(kind: "fuel", date: Date.current, odometer: 10_000, quantity: 40, amount: 70)
    create_transaction(name: "REPSOL", amount: 65, category: @fuel)
    @linker.run!

    log.reload.reject_link!

    assert log.reload.persisted?
    assert_nil log.entry
    assert_nil log.suggestion
  end

  test "moves the charge from its pending copy to the record the user types later" do
    charge = create_transaction(name: "REPSOL", amount: 60, date: 1.day.ago.to_date, category: @fuel)
    @linker.run!
    pending = @vehicle.logs.find_by!(entry: charge)

    typed = @vehicle.logs.create!(kind: "fuel", date: 1.day.ago.to_date, odometer: 12_000, quantity: 38, amount: 58)
    AssetLinker.new(@family).run!

    assert_not Vehicle::Log.exists?(pending.id)
    assert_equal charge, typed.reload.entry
    assert_equal "link", typed.suggestion
  end

  test "leaves charges alone when several vehicles could own them and nothing says which" do
    second = Account.create!(family: @family, owner: users(:family_admin), name: "Second car", balance: 5000, currency: "USD",
                             accountable: Vehicle.new, status: "active")
    charge = create_transaction(name: "REPSOL", amount: 50, category: @fuel)

    AssetLinker.new(@family).run!
    assert_nil AssetLink.for_entry(charge)

    charge.transaction.tags << @family.tags.create!(name: "Second car")
    AssetLinker.new(@family).run!
    assert_equal second, AssetLink.for_entry(charge).asset_account
  end

  test "only looks a year back unless asked for the whole history" do
    old = create_transaction(name: "REPSOL", amount: 50, date: 2.years.ago.to_date, category: @fuel)

    @linker.run!
    assert_nil AssetLink.for_entry(old)

    AssetLinker.new(@family, since: nil).run!
    assert AssetLink.for_entry(old).present?
  end

  test "a charge cannot be linked to a vehicle and a property at once" do
    charge = create_transaction(name: "Mixed", amount: 80)
    @vehicle.logs.create!(kind: "expense", category: "other", date: Date.current, entry: charge)

    expense = @property.expenses.new(kind: "other", date: Date.current, entry: charge)
    assert_not expense.valid?
    assert expense.errors.of_kind?(:entry, :taken)
  end

  private
    def category(name)
      @family.categories.find_by(name: name) || @family.categories.create!(name: name, color: "#506cd8", lucide_icon: "shapes")
    end
end
