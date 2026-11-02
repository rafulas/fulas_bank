require "test_helper"

class Account::PinsToAdjustmentsTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "BBVA Mar&Me", balance: 760, cash_balance: 760, currency: "USD", accountable: Depository.new)
    @account.entries.create!(
      date: 20.days.ago.to_date, name: "Saldo inicial", amount: 1000, currency: "USD",
      entryable: Valuation.new(kind: "opening_anchor")
    )
    create_transaction(account: @account, name: "Compra", amount: 100, date: 15.days.ago.to_date)
    pin(800, 10.days.ago.to_date)                     # 900 -> fixed at 800
    create_transaction(account: @account, name: "Recibo", amount: 50, date: 5.days.ago.to_date)
    create_transaction(account: @account, name: "Traspaso", amount: 99.99, date: Date.current)
    pin(760, Date.current)                            # the transfer was swallowed here
  end

  test "fixed balances become adjustments and every balance stays the same" do
    before = balances_by_date

    result = Account::PinsToAdjustments.run(Account.where(id: @account.id))

    assert_equal [ @account ], result.converted
    assert_empty result.skipped
    assert_empty @account.reload.valuations.reconciliation
    assert_equal 1000, @account.valuations.opening_anchor.sole.entry.amount, "the opening balance stays"

    adjustments = Account::BalanceAdjuster.adjustments_for(@account).order(:date).to_a
    assert_equal [ 10.days.ago.to_date, Date.current ], adjustments.map(&:date)
    assert_equal [ 100, BigDecimal("-109.99") ], adjustments.map(&:amount)
    assert adjustments.all?(&:excluded?)

    assert_equal before, balances_by_date
  end

  test "afterwards a movement on the same day moves the balance" do
    Account::PinsToAdjustments.run(Account.where(id: @account.id))

    create_transaction(account: @account.reload, name: "Café", amount: 2, date: Date.current)

    assert_equal 758, Account::BalanceAdjuster.new(@account.reload).balance_on(Date.current)
  end

  test "a fixed balance from before the opening balance is just removed" do
    pin(5000, 25.days.ago.to_date)
    before = balances_by_date.select { |date, _| date >= 20.days.ago.to_date }

    Account::PinsToAdjustments.run(Account.where(id: @account.id))

    assert_empty @account.reload.valuations.reconciliation
    assert_not Account::BalanceAdjuster.adjustments_for(@account).where(date: 25.days.ago.to_date).exists?
    assert_equal before, balances_by_date.select { |date, _| date >= 20.days.ago.to_date }
  end

  test "value-tracked accounts keep their dated values" do
    house = @family.accounts.create!(name: "Casa", balance: 200_000, currency: "USD", accountable: Property.new)
    house.create_reconciliation(balance: 210_000, date: Date.current)

    Account::PinsToAdjustments.run(Account.where(id: [ @account.id, house.id ]))

    assert_equal 1, house.reload.valuations.reconciliation.count
  end

  test "running it again changes nothing" do
    Account::PinsToAdjustments.run(Account.where(id: @account.id))

    assert_no_difference "Entry.count" do
      result = Account::PinsToAdjustments.run(Account.where(id: @account.id))
      assert_empty result.converted
    end
  end

  private
    def pin(amount, date)
      @account.entries.create!(
        date: date, name: "Saldo actualizado", amount: amount, currency: "USD",
        entryable: Valuation.new(kind: "reconciliation")
      )
    end

    def balances_by_date
      Balance::ForwardCalculator.new(@account.reload).calculate.to_h { |row| [ row.date, row.balance.to_d ] }
    end
end
