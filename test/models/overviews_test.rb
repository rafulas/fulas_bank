require "test_helper"

class OverviewsTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @user = users(:empty)
  end

  test "loans: what is owed, what was borrowed and how much has been repaid" do
    @family.accounts.create!(name: "Hipoteca", balance: 150_000, currency: "USD",
                             accountable: Loan.new(initial_balance: 200_000, interest_rate: 2.5, term_months: 300, rate_type: "fixed"))

    overview = LoansOverview.new(@family, user: @user)
    row = overview.rows.first

    assert_equal Money.new(150_000, "USD"), row.pending
    assert_equal Money.new(200_000, "USD"), row.borrowed
    assert_in_delta 0.25, row.paid_ratio, 0.001
    assert_equal Money.new(150_000, "USD"), overview.total_pending
    assert_in_delta 0.25, overview.total_paid_ratio, 0.001
  end

  test "investments: value, money put in, gain and return" do
    fund = @family.accounts.create!(name: "Fondo", balance: 6_445, currency: "USD", accountable: Investment.new)
    @family.accounts.create!(name: "Acciones", balance: 1_000, currency: "USD", accountable: Investment.new)
    create_transaction(account: fund, name: "Aportación", amount: -5_000, date: Date.current - 300)
    create_transaction(account: fund, name: "Aportación", amount: -800, date: Date.current - 30)

    overview = InvestmentsOverview.new(@family, user: @user)
    fund_row = overview.rows.find { |row| row.account == fund }

    assert_equal Money.new(5_800, "USD"), fund_row.contributed
    assert_equal Money.new(645, "USD"), fund_row.gain
    assert_in_delta 0.1112, fund_row.return_ratio, 0.0001
    assert_nil overview.rows.find { |row| row.account.name == "Acciones" }.gain
    assert_equal Money.new(7_445, "USD"), overview.total_value
    assert_equal Money.new(645, "USD"), overview.total_gain
  end

  test "investments recorded purchase by purchase compare their value with what the shares cost" do
    account = @family.accounts.create!(name: "Acciones BBVA", balance: 1_000, currency: "USD", accountable: Investment.new(subtype: "stocks"))
    account.holdings.create!(security: securities(:aapl), date: Date.current, qty: 100, price: 10, amount: 1_000, currency: "USD", cost_basis: 3.4)

    row = InvestmentsOverview.new(@family, user: @user).rows.sole

    assert_equal Money.new(340, "USD"), row.contributed
    assert_equal Money.new(660, "USD"), row.gain
  end

  test "funds held by participaciones count what was put into them in the totals" do
    account = @family.accounts.create!(name: "Fondos", balance: "1017.41", currency: "USD", accountable: Investment.new)
    @family.investment_funds.create!(account: account, name: "Indexado", units: 100, price: "10.1741", price_date: Date.current, cost: 1_000)

    overview = InvestmentsOverview.new(@family, user: @user)
    row = overview.rows.sole

    assert_equal Money.new(1_000, "USD"), row.contributed
    assert_equal Money.new(1_000, "USD"), overview.total_contributed
    assert_equal Money.new("17.41", "USD"), overview.total_gain
  end

  test "Fulas Bank: current accounts and loans offer only the kinds that exist in Spain" do
    assert_equal %w[checking savings cash], Depository.subtype_options_for_select.map(&:last)
    assert_includes Depository.subtype_options_for_select(current: "hsa").map(&:last), "hsa"
    assert_not_includes Loan.subtype_options_for_select.map(&:last), "student"
    assert_includes Loan.subtype_options_for_select(current: "student").map(&:last), "student"
  end

  test "the investment types offered are the Spanish ones, keeping an account's own" do
    assert_equal %w[stocks mutual_fund pension savings_insurance fixed_income other], Investment.subtypes_for_select.map(&:last)
    assert_includes Investment.subtypes_for_select(current: "401k").map(&:last), "401k"
  end
end
