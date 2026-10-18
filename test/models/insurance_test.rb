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

  test "a premium paid in custom instalments costs what they add up to" do
    insurance = @family.insurances.new(
      name: "Coche", kind: "car", payment_frequency: "custom",
      installments: [
        { "date" => "2026-12-01", "amount" => "150" },
        { "date" => "2026-09-01", "amount" => "150,50" },
        { "date" => "", "amount" => "" },
        { "date" => "2026-10-16", "amount" => "150" }
      ]
    )

    assert insurance.valid?
    assert_equal %w[2026-09-01 2026-10-16 2026-12-01], insurance.installments.map { |row| row["date"] }
    assert_equal 3, insurance.payments_per_year
    assert_equal BigDecimal("450.5"), insurance.annual_cost.amount
    assert_in_delta 37.54, insurance.monthly_cost.amount.to_f, 0.01
  end

  test "the next instalment repeats the instalment days every year" do
    insurance = @family.insurances.new(
      name: "Moto", kind: "motorcycle", payment_frequency: "custom",
      installments: [ { "date" => "2025-09-01", "amount" => "100" }, { "date" => "2025-10-16", "amount" => "90" } ]
    )

    date, amount = insurance.next_installment(Date.new(2026, 10, 1))
    assert_equal Date.new(2026, 10, 16), date
    assert_equal BigDecimal("90"), amount.amount

    assert_equal Date.new(2027, 9, 1), insurance.next_installment(Date.new(2026, 10, 17)).first
  end

  test "custom instalments need at least one, with a date and an amount" do
    insurance = @family.insurances.new(name: "Coche", kind: "car", payment_frequency: "custom")
    assert_not insurance.valid?
    assert insurance.errors.added?(:installments, :blank)

    insurance.installments = [ { "date" => "2026-09-01", "amount" => "" } ]
    assert_not insurance.valid?
    assert insurance.errors.added?(:installments, :invalid)

    insurance.installments = [ { "date" => "2026-09-01", "amount" => "-5" } ]
    assert_not insurance.valid?
  end

  test "a policy paid every quarter is charged every three months from its renewal day" do
    insurance = @family.insurances.new(name: "Coche", kind: "car", premium: 160, payment_frequency: "quarterly", renewal_date: Date.new(2026, 2, 15))

    charges = insurance.periodic_charges_between(Date.new(2026, 10, 1)..Date.new(2027, 6, 30))
    assert_equal [ Date.new(2026, 11, 15), Date.new(2027, 2, 15), Date.new(2027, 5, 15) ], charges.map(&:first)
    assert charges.all? { |_, amount| amount.amount == 160 }
  end

  test "a policy that will not be renewed ends at its next renewal and is cancelled then" do
    insurance = @family.insurances.create!(name: "Moto", kind: "motorcycle", premium: 300, payment_frequency: "annual",
                                           renewal_date: 1.year.ago.to_date + 10)
    insurance.update!(renews: "0")

    assert_equal insurance.next_renewal, insurance.ends_on
    assert_not insurance.renews?

    Insurance.expire_ended!(insurance.ends_on - 1)
    assert insurance.reload.active?

    Insurance.expire_ended!(insurance.ends_on)
    assert_not insurance.reload.active?

    insurance.update!(renews: "1")
    assert_nil insurance.ends_on
  end

  test "it cannot be set not to renew without a renewal date" do
    insurance = @family.insurances.new(name: "Viaje", kind: "travel", premium: 40, payment_frequency: "annual", renews: "0")

    assert_not insurance.valid?
    assert insurance.errors.added?(:renewal_date, :needed_to_end)
  end
end
