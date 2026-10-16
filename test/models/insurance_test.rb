require "test_helper"

class InsuranceTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "the yearly and monthly cost follow the payment frequency" do
    insurance = @family.insurances.new(name: "Hogar", kind: "home", premium: 30, payment_frequency: "monthly")

    assert_equal BigDecimal("360"), insurance.annual_cost.amount
    assert_equal BigDecimal("30"), insurance.monthly_cost.amount

    insurance.payment_frequency = "semiannual"
    assert_equal BigDecimal("60"), insurance.annual_cost.amount

    insurance.premium = nil
    assert_nil insurance.annual_cost
  end

  test "takes the currency of the asset it insures" do
    insurance = @family.insurances.create!(name: "Coche", kind: "car", account: accounts(:vehicle))

    assert_equal accounts(:vehicle).currency, insurance.currency
  end

  test "renews every year on the same day" do
    today = Date.new(2026, 10, 16)
    insurance = @family.insurances.new(name: "Coche", renewal_date: Date.new(2024, 10, 24))

    assert_equal Date.new(2026, 10, 24), insurance.next_renewal(today)
    assert_equal 8, insurance.days_to_renewal(today)
    assert insurance.renews_soon?(today)

    insurance.renewal_date = Date.new(2025, 3, 1)
    assert_equal Date.new(2027, 3, 1), insurance.next_renewal(today)
    assert_not insurance.renews_soon?(today)

    insurance.renewal_date = Date.new(2027, 1, 5)
    assert_equal Date.new(2027, 1, 5), insurance.next_renewal(today)
  end

  test "a cancelled policy is never flagged for renewal" do
    insurance = @family.insurances.new(name: "Coche", active: false, renewal_date: Date.current + 3)

    assert_not insurance.renews_soon?
  end

  test "a car or motorbike policy insures a vehicle and a home policy a property" do
    assert @family.insurances.new(name: "Coche", kind: "car", account: accounts(:vehicle)).valid?
    assert @family.insurances.new(name: "Moto", kind: "motorcycle", account: accounts(:vehicle)).valid?
    assert @family.insurances.new(name: "Hogar", kind: "home", account: accounts(:property)).valid?

    wrong = @family.insurances.new(name: "Hogar", kind: "home", account: accounts(:vehicle))
    assert_not wrong.valid?
    assert wrong.errors.of_kind?(:account, :wrong_type)

    # Other kinds may be tied to any vehicle or property, or to none.
    assert @family.insurances.new(name: "Responsabilidad civil", kind: "liability", account: accounts(:property)).valid?
    assert @family.insurances.new(name: "Vida", kind: "life").valid?
  end

  test "only a vehicle or property of the same family can be insured" do
    assert_not @family.insurances.new(name: "Cuenta", kind: "other", account: accounts(:depository)).valid?

    foreign = Account.create!(family: families(:empty), name: "Foreign car", balance: 1_000, currency: "USD", accountable: Vehicle.new)
    assert_not @family.insurances.new(name: "Coche", kind: "car", account: foreign).valid?
  end

  test "deleting the asset keeps the policy, unlinked" do
    insurance = @family.insurances.create!(name: "Coche", kind: "car", account: accounts(:vehicle))

    accounts(:vehicle).destroy!

    assert_nil insurance.reload.account_id
  end

  test "suggests the kind for an asset" do
    assert_equal "car", Insurance.kind_for(accounts(:vehicle))
    assert_equal "home", Insurance.kind_for(accounts(:property))
    assert_equal "other", Insurance.kind_for(nil)
  end
end
