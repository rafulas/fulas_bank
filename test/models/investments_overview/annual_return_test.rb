require "test_helper"

class InvestmentsOverview::AnnualReturnTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @today = Date.new(2026, 10, 15)
  end

  test "a contribution that doubled in a year is 100 % a year" do
    fund = investment("Fondo", balance: 2_000)
    contribute(fund, 1_000, @today - 365)

    assert_in_delta 1.0, annual_return([ fund ]).rate_for(fund), 0.001
  end

  test "money put in recently weighs less than money put in long ago" do
    fund = investment("Fondo", balance: 2_100)
    contribute(fund, 1_000, @today - 365)
    contribute(fund, 1_000, @today - 30)

    rate = annual_return([ fund ]).rate_for(fund)

    # A simple return would be 5 %; the old euro carried most of the gain.
    assert_operator rate, :>, 0.05
    assert_operator rate, :<, 0.11
  end

  test "adds the accounts together, and leaves out those with nothing to measure" do
    fund = investment("Fondo", balance: 1_100)
    contribute(fund, 1_000, @today - 365)
    shares = investment("Acciones", balance: 2_400)
    contribute(shares, 2_000, @today - 365)
    by_hand = investment("Fondo a mano", balance: 5_000)

    result = annual_return([ fund, shares, by_hand ])

    assert_equal [ fund, shares ], result.measured
    # 3_000 put in a year ago are worth 3_500 today.
    assert_in_delta 500.0 / 3_000, result.rate, 0.001
  end

  private
    def annual_return(accounts)
      InvestmentsOverview::AnnualReturn.new(accounts, currency: "EUR", today: @today)
    end

    def investment(name, balance:)
      @family.accounts.create!(name: name, balance: balance, currency: "EUR", accountable: Investment.new)
    end

    def contribute(account, amount, date)
      create_transaction(account: account, name: "Aportación", amount: -amount, date: date, currency: "EUR")
    end
end
