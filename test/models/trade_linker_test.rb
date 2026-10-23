require "test_helper"

class TradeLinkerTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @trade_entry = entries(:trade) # buy of 10 AAPL for 2140, a day ago
    @trade = @trade_entry.trade
    @investment = @trade_entry.account
    @investment.accountable.update_column(:brokerage_cash, false)
    @checking = accounts(:depository)
  end

  def bank_entry(amount:, date: @trade_entry.date)
    @checking.entries.create!(name: "Compra acciones", date: date, amount: amount, currency: "USD", entryable: Transaction.new)
  end

  test "proposes the bank movement of the same amount for a buy without brokerage cash" do
    charge = bank_entry(amount: 2140, date: @trade_entry.date - 2.days)

    assert_equal 1, TradeLinker.new(@family).run!

    @trade.reload
    assert_equal charge, @trade.bank_entry
    assert @trade.bank_entry_suggested?
  end

  test "does not propose a movement whose amount is far from the trade's" do
    bank_entry(amount: 1500)

    assert_equal 0, TradeLinker.new(@family).run!
    assert_nil @trade.reload.bank_entry
  end

  test "leaves alone accounts with brokerage cash and trades already linked" do
    @investment.accountable.update_column(:brokerage_cash, true)
    bank_entry(amount: 2140)

    assert_equal 0, TradeLinker.new(@family).run!
  end

  test "never proposes again a movement rejected for the account" do
    charge = bank_entry(amount: 2140)
    AssetLinkRejection.create!(entry: charge, account: @investment)

    assert_equal 0, TradeLinker.new(@family).run!
  end

  test "a failure is kept in the debug log and does not stop the sync" do
    TradeLinker.any_instance.stubs(:run!).raises(StandardError, "boom")

    assert_difference -> { DebugLogEntry.where(source: "TradeLinker", level: "error").count }, 1 do
      assert_equal 0, TradeLinker.run_quietly(@family)
    end
  end
end
