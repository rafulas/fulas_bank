require "test_helper"

class Insurance::OverviewTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @today = Date.new(2026, 10, 16)
    @assets = [ accounts(:property), accounts(:vehicle) ]
  end

  test "adds up what the policies in force cost and lists the ones that renew soon" do
    car = @family.insurances.create!(name: "Coche", kind: "car", account: accounts(:vehicle), premium: 300, renewal_date: Date.new(2025, 10, 24))
    @family.insurances.create!(name: "Salud", kind: "health", premium: 50, payment_frequency: "monthly", renewal_date: Date.new(2026, 1, 1))
    @family.insurances.create!(name: "Antiguo", kind: "car", premium: 999, active: false)

    overview = Insurance::Overview.new(@family, assets: @assets, today: @today)

    assert_equal %w[Coche Salud], overview.active.map(&:name)
    assert_equal %w[Antiguo], overview.inactive.map(&:name)
    assert_equal BigDecimal("900"), overview.annual_total.amount
    assert_equal BigDecimal("75"), overview.monthly_total.amount
    assert_equal [ car ], overview.renewing_soon
    assert_equal car, overview.next_renewal
  end

  test "lists the vehicles and properties without a policy in force" do
    @family.insurances.create!(name: "Coche", kind: "car", account: accounts(:vehicle))
    @family.insurances.create!(name: "Hogar antiguo", kind: "home", account: accounts(:property), active: false)

    overview = Insurance::Overview.new(@family, assets: @assets, today: @today)

    assert_equal [ accounts(:property) ], overview.uninsured_assets
  end

  test "with no policies the totals are zero" do
    overview = Insurance::Overview.new(@family, assets: @assets, today: @today)

    assert overview.empty?
    assert_equal 0, overview.annual_total.amount
    assert_nil overview.next_renewal
  end
end
