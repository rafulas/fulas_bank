require "test_helper"

class Demo::FulasGeneratorTest < ActiveSupport::TestCase
  EMAIL = "ejemplo@example.com".freeze

  test "creates the Spanish example family with every Fulas Bank record" do
    family = Demo::FulasGenerator.new(seed: 7).generate!(email: EMAIL)

    assert_equal [ "EUR", "es", "ES" ], [ family.currency, family.locale, family.country ]
    assert_equal [ EMAIL, "partner_#{EMAIL}" ].sort, family.users.pluck(:email).sort
    assert family.users.find_by(email: EMAIL).authenticate(Demo::FulasGenerator::PASSWORD)

    assert_equal 8, family.accounts.count
    assert family.accounts.all? { |account| account.currency == "EUR" }

    transactions = Transaction.joins(:entry).where(entries: { account_id: family.accounts.select(:id) })
    assert_operator transactions.count, :>, 400
    assert_operator transactions.where.not(category_id: nil).count, :>, 300
    assert transactions.joins(:category).where(categories: { name: "Supermercado" }).exists?

    vehicle = family.accounts.find_by!(accountable_type: "Vehicle").vehicle
    assert_operator vehicle.logs.fuels.where(suggestion: nil).count, :>, 25
    assert vehicle.logs.services.exists?
    assert vehicle.logs.expenses.where(category: "insurance").exists?
    assert_equal 4, vehicle.maintenance_items.count
    # The two latest refuels are left for the app, which proposes them.
    assert_equal 2, vehicle.logs.pending.fuels.count

    property = family.accounts.find_by!(accountable_type: "Property").property
    assert property.expenses.settled.where(kind: "mortgage").exists?
    assert property.expenses.settled.where(kind: "utilities").exists?
    assert_equal 1, property.expenses.pending.where(kind: "community").count

    assert_operator family.recurring_transactions.count, :>=, 5
    assert_equal 3, family.budgets.count
    assert_equal 2, family.forecast_items.count

    broker = family.accounts.find_by!(name: "Bróker acciones")
    assert broker.holdings.where(date: Date.current).where("qty > 0").exists?
    assert_operator family.accounts.find_by!(name: "Cuenta nómina").balance, :>, 0
  end

  test "replaces only the previous example family" do
    old = Family.create!(name: "Demo Family")
    old.users.create!(email: EMAIL, first_name: "Jack", last_name: "Bogle", role: "admin", password: "Password1!")
    kept = families(:dylan_family)

    Demo::FulasGenerator.new.send(:remove_previous_family!, EMAIL)

    assert_not Family.exists?(old.id)
    assert Family.exists?(kept.id)
  end

  test "refuses to run outside development and test" do
    Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("production"))

    assert_raises(SecurityError) { Demo::FulasGenerator.new.generate!(email: EMAIL) }
  end
end
