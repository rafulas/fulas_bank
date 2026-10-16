require "test_helper"

class Trades::BankLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @trade_entry = entries(:trade)
    @trade_entry.account.accountable.update_column(:brokerage_cash, false)
    @charge = accounts(:depository).entries.create!(
      name: "Compra acciones", date: @trade_entry.date, amount: 2140, currency: "USD", entryable: Transaction.new
    )
  end

  test "links a trade to a bank movement and shows it on both sides" do
    post trade_bank_link_path(@trade_entry), params: { bank_entry_id: @charge.id }

    assert_redirected_to account_path(@trade_entry.account)
    assert_equal @charge, @trade_entry.trade.reload.bank_entry

    get trade_path(@trade_entry)
    assert_response :success
    assert_select "a[href=?]", transaction_path(@charge)

    get transaction_path(@charge)
    assert_response :success
    assert_select "a[href=?]", trade_path(@trade_entry)
  end

  test "offers the matching bank movements in the trade drawer" do
    get trade_path(@trade_entry)

    assert_response :success
    assert_select "form[action=?]", trade_bank_link_path(@trade_entry, bank_entry_id: @charge.id)
  end

  test "unlinks a trade" do
    @trade_entry.trade.update!(bank_entry: @charge)

    delete trade_bank_link_path(@trade_entry)

    assert_nil @trade_entry.trade.reload.bank_entry
  end

  test "cannot link a movement of another family" do
    other = families(:empty).accounts.create!(name: "Other", balance: 0, currency: "USD", accountable: Depository.new)
    foreign = other.entries.create!(name: "Foreign", date: @trade_entry.date, amount: 2140, currency: "USD", entryable: Transaction.new)

    post trade_bank_link_path(@trade_entry), params: { bank_entry_id: foreign.id }

    assert_response :not_found
    assert_nil @trade_entry.trade.reload.bank_entry
  end

  test "confirms a proposal, and rejects another for good" do
    @trade_entry.trade.update!(bank_entry: @charge, bank_entry_suggested: true)

    patch confirm_trade_bank_link_path(@trade_entry)
    assert_not @trade_entry.trade.reload.bank_entry_suggested?
    assert_equal @charge, @trade_entry.trade.bank_entry

    @trade_entry.trade.update!(bank_entry_suggested: true)
    delete reject_trade_bank_link_path(@trade_entry)

    assert_nil @trade_entry.trade.reload.bank_entry
    assert AssetLinkRejection.exists?(entry_id: @charge.id, account_id: @trade_entry.account_id)
    assert_equal 0, TradeLinker.new(@trade_entry.account.family).run!
  end

  test "confirms every proposal from Inversiones" do
    @trade_entry.trade.update!(bank_entry: @charge, bank_entry_suggested: true)

    get investments_overview_path
    assert_select "#suggested_trades"

    post confirm_bank_links_trades_path
    assert_not @trade_entry.trade.reload.bank_entry_suggested?
  end
end
