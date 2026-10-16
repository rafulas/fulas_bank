require "test_helper"

class CashCushionTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @user = users(:empty)
    @family.accounts.create!(name: "Cuenta", owner: @user, balance: 6_000, currency: @family.currency, accountable: Depository.new)
    @family.accounts.create!(name: "Fondo", owner: @user, balance: 50_000, currency: @family.currency, accountable: Investment.new)
  end

  test "months of typical spending the cash in accounts covers" do
    cushion = CashCushion.new(@family, user: @user)
    IncomeStatement.any_instance.stubs(:median_expense).returns(1_500)

    assert_equal Money.new(6_000, @family.currency), cushion.cash
    assert_equal 4.0, cushion.months
    assert_equal :ok, cushion.level
  end

  test "below three months is low; with no spending there is nothing to say" do
    IncomeStatement.any_instance.stubs(:median_expense).returns(3_000)
    assert_equal :low, CashCushion.new(@family, user: @user).level

    IncomeStatement.any_instance.stubs(:median_expense).returns(0)
    assert_nil CashCushion.new(@family, user: @user).months
  end
end
