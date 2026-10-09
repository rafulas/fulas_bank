require "test_helper"

class Category::SummaryTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = Family.create!(name: "Summary Family", currency: "USD")
    @family.apply_default_categories!
    @checking = @family.accounts.create!(name: "Checking", currency: "USD", balance: 5000, accountable: Depository.new)
    @savings = @family.accounts.create!(name: "Savings", currency: "USD", balance: 1000, accountable: Depository.new)
    @period = Period.last_30_days
  end

  test "totals each root category with its subcategories, expenses negative" do
    food = category("Comida y bebida")
    create_transaction(account: @checking, amount: 100, category: category("Supermercado"))
    create_transaction(account: @checking, amount: 25, category: category("Café y aperitivos"))
    create_transaction(account: @checking, amount: 10, category: food)
    create_transaction(account: @checking, amount: -2000, category: category("Nómina"))

    summary = summary_for

    assert_equal(-135, summary.total_for(food))
    assert_equal 2000, summary.total_for(category("Ingresos"))

    own, subs = summary.breakdown(food)
    assert_equal(-10, own.total)
    assert_equal [ "Supermercado", "Café y aperitivos" ], subs.first(2).map { |row| row.category.name }
    assert_equal(-100, subs.first.total)
  end

  test "lists categories with an amount first, Traspasos next and Excluido last" do
    create_transaction(account: @checking, amount: 50, category: category("Combustible"))
    create_transaction(account: @checking, amount: 300, category: category("Comunidad"))

    rows = summary_for.rows
    names = rows.map { |row| row.category.name }

    assert_equal [ "Hogar", "Transporte", "Traspasos" ], names.first(3)
    assert_equal "Excluido", names.last
    assert rows.one?(&:uncategorized?)
  end

  test "Traspasos counts its own transactions and matched transfers" do
    create_transaction(account: @checking, amount: 200, category: @family.categories.find_by!(special: "transfers"))
    create_transaction(account: @checking, amount: 100, kind: "funds_movement")
    create_transaction(account: @savings, amount: -100, kind: "funds_movement")

    row = summary_for.rows.find(&:transfers?)

    assert_equal 3, row.count
    assert_equal 0, summary_for.rows.find(&:uncategorized?).count
  end

  test "Excluido shows its total apart, and transactions excluded by hand don't count" do
    create_transaction(account: @checking, amount: 80, category: @family.categories.find_by!(special: "excluded"))
    create_transaction(account: @checking, amount: 40, category: category("Supermercado"), excluded: true)

    summary = summary_for

    assert_equal(-80, summary.rows.find(&:excluded?).total)
    assert_equal 0, summary.total_for(category("Comida y bebida"))
  end

  test "uncategorized transactions show as Sin definir" do
    create_transaction(account: @checking, amount: 30)

    row = summary_for.rows.find(&:uncategorized?)

    assert_equal(-30, row.total)
    assert_equal 1, row.count
  end

  test "only counts the given accounts" do
    create_transaction(account: @savings, amount: 70, category: category("Supermercado"))

    summary = Category::Summary.new(@family, period: @period, account_ids: [ @checking.id ])

    assert_equal 0, summary.total_for(category("Comida y bebida"))
  end

  private
    def category(name)
      @family.categories.find_by!(name: name)
    end

    def summary_for
      Category::Summary.new(@family, period: @period)
    end
end
