require "test_helper"

class CashCushionTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @user = users(:empty)
    @account = @family.accounts.create!(name: "Cuenta", owner: @user, balance: 6_000, currency: @family.currency, accountable: Depository.new)
    @family.accounts.create!(name: "Fondo", owner: @user, balance: 50_000, currency: @family.currency, accountable: Investment.new)
    @today = Date.new(2026, 10, 31)
  end

  test "months of typical spending the cash in accounts covers" do
    cushion = CashCushion.new(@family, user: @user, today: @today)
    cushion.stubs(:month_totals).returns([ 1_500, 1_500, 1_500 ])

    assert_equal Money.new(6_000, @family.currency), cushion.cash
    assert_equal 4.0, cushion.months
    assert_equal :ok, cushion.level
  end

  test "below three months is low; with no spending there is nothing to say" do
    low = CashCushion.new(@family, user: @user, today: @today)
    low.stubs(:month_totals).returns([ 3_000 ])
    assert_equal :low, low.level

    assert_nil CashCushion.new(@family, user: @user, today: @today).months, "no movements, no months"
  end

  test "typical spending: the last finished months with history, without the highest and the lowest" do
    { 1 => 2_000, 2 => 1_800, 3 => 9_000, 4 => 50 }.each do |back, amount|
      create_transaction(account: @account, amount: amount, date: (@today.beginning_of_month << back) + 3)
    end
    create_transaction(account: @account, amount: 5_000, date: @today)

    cushion = CashCushion.new(@family, user: @user, today: @today)

    assert_equal 4, cushion.month_totals.size, "months before the first movement and this month do not count"
    assert_equal Money.new(1_900, @family.currency), cushion.monthly_expense, "9.000 and 50 are left out"
  end
end
