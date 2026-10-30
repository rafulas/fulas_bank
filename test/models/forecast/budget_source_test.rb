require "test_helper"

class Forecast::BudgetSourceTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @today = Date.current
    @next_month = @today.beginning_of_month.next_month
    @account = Account.create!(family: @family, owner: @user, name: "Presupuesto checking", balance: 1_000,
                               currency: "USD", accountable: Depository.new, status: "active")
    @insurance = @family.categories.create!(name: "Seguros prueba", color: "#000000")
    @food = categories(:food_and_drink)
  end

  test "the recurring payments of a month go to their main category" do
    sub = @family.categories.create!(name: "Seguro coche prueba", color: "#000000", parent: @insurance)
    series(name: "Mapfre", amount: 47, category: sub)
    series(name: "Nómina", amount: -2_000, category: @food)

    expected = Forecast::CategoryRecurring.new(@family).for(@next_month)

    assert_equal BigDecimal("47"), expected[@insurance.id.to_s], "a subcategory counts in its main one"
    assert_nil expected[@food.id.to_s], "income is not a recurring expense"
  end

  test "a category with a budget counts its budget minus its recurring payments, the others their average" do
    series(name: "Mapfre", amount: 47, category: @insurance)
    MonthBudget.new(@family, user: @user, month: @next_month).save!(@insurance.id => "100")
    other = @family.categories.create!(name: "Otro prueba", color: "#000000")
    [ 2, 3 ].each do |back|
      month = @today.beginning_of_month << back
      create_transaction(account: @account, name: "Súper", amount: 200, date: month + 4, category: other)
      create_transaction(account: @account, name: "Seguro raro", amount: 900, date: month + 5, category: @insurance)
    end

    source = Forecast::BudgetSource.new(@family, user: @user, today: @today)
    assert_equal({ @insurance.id.to_s => BigDecimal("53") }, source.variable_parts(@next_month).slice(@insurance.id.to_s))

    estimate = Forecast::VariableEstimate.new(@family, accounts: [ @account ], today: @today, budget_source: source)
    # The insurance's own history (900) gives way to its budget: 200 + 53.
    assert_equal BigDecimal("253"), estimate.combined_monthly(@next_month)
    assert_equal BigDecimal("1100"), Forecast::VariableEstimate.new(@family, accounts: [ @account ], today: @today).combined_monthly(@next_month)
  end

  test "the planner builds each month's budget from the variable estimate plus that month's bills" do
    series(name: "Mapfre", amount: 47, category: @insurance)
    [ 2, 3 ].each do |back|
      create_transaction(account: @account, name: "Súper", amount: 300.4, date: (@today.beginning_of_month << back) + 4, category: @food)
    end

    planner = Forecast::BudgetPlanner.new(@family, user: @user, accounts: [ @account ], today: @today)
    amounts = planner.amounts_for(@next_month)

    assert_equal BigDecimal("301"), amounts[@food.id.to_s], "rounded up to whole euros"
    assert_equal BigDecimal("47"), amounts[@insurance.id.to_s]
    assert_equal 60, planner.months.size
  end

  private
    def series(name:, amount:, category:)
      day = 10
      @family.recurring_transactions.create!(
        account: @account, name: name, amount: amount, currency: "USD", category: category,
        expected_day_of_month: day, status: "active", manual: true, bill_type: "bill",
        last_occurrence_date: @today.beginning_of_month.change(day: day), next_expected_date: @next_month.change(day: day)
      )
    end
end
