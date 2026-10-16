require "test_helper"

class Trade::BankLinkTest < ActiveSupport::TestCase
  setup do
    @trade_entry = entries(:trade)
    @trade = @trade_entry.trade
    @investment = @trade_entry.account
    @investment.accountable.update_column(:brokerage_cash, false)
    @investment.reload
    @checking = accounts(:depository)
    @scope = families(:dylan_family).entries
  end

  def bank_entry(amount:, date: @trade_entry.date, account: @checking, name: "Bank movement")
    account.entries.create!(name: name, date: date, amount: amount, currency: "USD", entryable: Transaction.new)
  end

  test "a buy in an account without brokerage cash can be linked to the bank charge that paid for it" do
    charge = bank_entry(amount: 2140)

    assert @trade.bank_linkable?
    assert @trade.update(bank_entry: charge)
    assert_equal @trade, charge.reload.linked_trade
  end

  test "trades of an account with brokerage cash are not linkable" do
    @investment.accountable.update_column(:brokerage_cash, true)
    @investment.reload
    charge = bank_entry(amount: 2140)

    assert_not @trade.reload.bank_linkable?
    assert_not @trade.update(bank_entry: charge)
  end

  test "candidates are money out for a buy, around its date, closest amount first" do
    close = bank_entry(amount: 2150, date: @trade_entry.date + 2.days, name: "Close")
    exact = bank_entry(amount: 2140, date: @trade_entry.date - 5.days, name: "Exact")
    income = bank_entry(amount: -2140, name: "Income")
    too_late = bank_entry(amount: 2140, date: @trade_entry.date + 20.days, name: "Too late")

    candidates = @trade.bank_entry_candidates(scope: @scope)

    assert_equal [ exact, close ], candidates.first(2)
    assert_not_includes candidates, income
    assert_not_includes candidates, too_late
  end

  test "a sale is offered money coming in" do
    @trade.update!(qty: -10)
    @trade_entry.update!(amount: -2140)
    proceeds = bank_entry(amount: -2140)
    charge = bank_entry(amount: 2140)

    candidates = @trade.reload.bank_entry_candidates(scope: @scope)

    assert_includes candidates, proceeds
    assert_not_includes candidates, charge
  end

  test "a bank movement already linked to another trade is not offered again" do
    charge = bank_entry(amount: 2140)
    other = @investment.entries.create!(
      name: "Buy 1 AAPL", date: @trade_entry.date, amount: 214, currency: "USD",
      entryable: Trade.new(security: securities(:aapl), qty: 1, price: 214, currency: "USD", investment_activity_label: "Buy")
    )
    other.trade.update!(bank_entry: charge)

    assert_not_includes @trade.bank_entry_candidates(scope: @scope), charge
    assert_not @trade.update(bank_entry: charge)
  end

  test "a movement of the investment account itself cannot be linked" do
    own = bank_entry(amount: 2140, account: @investment)

    assert_not @trade.update(bank_entry: own)
  end

  test "deleting the bank movement leaves the trade unlinked" do
    charge = bank_entry(amount: 2140)
    @trade.update!(bank_entry: charge)

    charge.destroy!

    assert_nil @trade.reload.bank_entry_id
  end
end
