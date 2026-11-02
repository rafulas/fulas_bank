require "test_helper"

class Account::BalanceAdjusterTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "BBVA", balance: 950, cash_balance: 950, currency: "USD", accountable: Depository.new)
    @account.entries.create!(
      date: 30.days.ago.to_date, name: "Saldo inicial", amount: 1000, currency: "USD",
      entryable: Valuation.new(kind: "opening_anchor")
    )
    create_transaction(account: @account, name: "Compra", amount: 50, date: 5.days.ago.to_date)
  end

  test "the balance is the running total of the movements" do
    assert_equal 950, adjuster.balance_on(Date.current)
    assert_equal 1000, adjuster.balance_on(10.days.ago.to_date)
  end

  test "typing the bank's balance writes an adjustment for the difference, and later movements still count" do
    result = adjuster.adjust_to(balance: 1000)

    assert result.success?
    assert_equal 50, result.adjustment_amount
    adjustment = Account::BalanceAdjuster.adjustments_for(@account).sole
    assert_equal Date.current, adjustment.date
    assert_equal(-50, adjustment.amount, "money in for an asset")
    assert adjustment.excluded?
    assert Account::BalanceAdjuster.adjustment?(adjustment)
    assert_equal 1000, adjuster.balance_on(Date.current)

    # The case from 2/11/2026: a transfer out entered after the balance was
    # typed, with today's date, has to lower it.
    create_transaction(account: @account, name: "Traspaso a BBVA Rafa", amount: 99.99, date: Date.current)

    assert_in_delta 900.01, adjuster.balance_on(Date.current), 0.001
  end

  test "Bilance's example: 1.000 €, a 2 € coffee, then 150 € imported the next day" do
    adjuster.adjust_to(balance: 1000)
    create_transaction(account: @account, name: "Café", amount: 2, date: Date.current)
    assert_equal 998, adjuster.balance_on(Date.current)

    create_transaction(account: @account, name: "Importado 1", amount: 100, date: Date.current)
    create_transaction(account: @account, name: "Importado 2", amount: 30, date: Date.current)
    create_transaction(account: @account, name: "Importado 3", amount: 20, date: Date.current)
    assert_equal 848, adjuster.balance_on(Date.current)
  end

  test "adjusting twice the same day changes the same adjustment, and removes it when nothing is left" do
    adjuster.adjust_to(balance: 1000)
    adjuster.adjust_to(balance: 1010)

    assert_equal(-60, Account::BalanceAdjuster.adjustments_for(@account).sole.amount)
    assert_equal 1010, adjuster.balance_on(Date.current)

    adjuster.adjust_to(balance: 950)

    assert_empty Account::BalanceAdjuster.adjustments_for(@account)
    assert_equal 950, adjuster.balance_on(Date.current)
  end

  test "the same balance needs no adjustment" do
    result = adjuster.adjust_to(balance: 950)

    assert result.success?
    assert_equal 0, result.adjustment_amount
    assert_empty Account::BalanceAdjuster.adjustments_for(@account)
  end

  test "a dry run says the difference and writes nothing" do
    assert_no_difference "@account.entries.count" do
      result = adjuster.adjust_to(balance: 900, dry_run: true)
      assert_equal(-50, result.adjustment_amount)
      assert_equal 950, result.old_balance
      assert_equal 900, result.new_balance
    end
  end

  test "on a past day it moves that day and everything after" do
    adjuster.adjust_to(balance: 1100, date: 10.days.ago.to_date)

    assert_equal 1100, adjuster.balance_on(10.days.ago.to_date)
    assert_equal 1050, adjuster.balance_on(Date.current)
  end

  test "a card is a debt: lowering it is money in" do
    card = @family.accounts.create!(name: "Tarjeta", balance: 300, cash_balance: 300, currency: "USD", accountable: CreditCard.new)
    card.entries.create!(
      date: 30.days.ago.to_date, name: "Saldo inicial", amount: 300, currency: "USD",
      entryable: Valuation.new(kind: "opening_anchor")
    )
    create_transaction(account: card, name: "Compra", amount: 20, date: 2.days.ago.to_date)

    Account::BalanceAdjuster.new(card).adjust_to(balance: 310)

    assert_equal(-10, Account::BalanceAdjuster.adjustments_for(card).sole.amount)
    assert_equal 310, Account::BalanceAdjuster.new(card).balance_on(Date.current)
  end

  test "«Nuevo saldo» on a current account writes an adjustment; on a value-tracked account, a dated value" do
    assert_difference -> { Account::BalanceAdjuster.adjustments_for(@account).count } => 1 do
      assert_no_difference -> { @account.entries.where(entryable_type: "Valuation").count } do
        assert @account.create_reconciliation(balance: 1200, date: Date.current).success?
      end
    end

    house = @family.accounts.create!(name: "Casa", balance: 200_000, currency: "USD", accountable: Property.new)
    assert_difference -> { house.entries.where(entryable_type: "Valuation").count } => 1 do
      assert house.create_reconciliation(balance: 210_000, date: Date.current).success?
    end
  end

  test "only for manual current accounts and cards" do
    assert Account::BalanceAdjuster.applies_to?(@account)
    assert_not Account::BalanceAdjuster.applies_to?(accounts(:other_asset))
    assert_not Account::BalanceAdjuster.applies_to?(accounts(:loan))
  end

  private
    def adjuster
      Account::BalanceAdjuster.new(@account.reload)
    end
end
