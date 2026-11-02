require "test_helper"

class Account::CurrentBalanceManagerTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @linked_account = accounts(:connected)

    # Create account_provider to make the account actually linked
    # (The fixture has plaid_account but that's the legacy association)
    @linked_account.account_providers.find_or_create_by!(
      provider_type: "PlaidAccount",
      provider_id: plaid_accounts(:one).id
    )
  end

  # -------------------------------------------------------------------------------------------------
  # Manual account current balance management
  #
  # Manual accounts do not manage `current_anchor` valuations and have "auto-update strategies" to set the current balance.
  # -------------------------------------------------------------------------------------------------

  test "when one or more reconciliations exist, append new reconciliation to represent the current balance" do
    account = @family.accounts.create!(
      name: "Test",
      balance: 1000,
      cash_balance: 1000,
      currency: "USD",
      accountable: Depository.new
    )

    # A reconciliation tells us that the user is tracking this account's value with balance-only updates
    account.entries.create!(
      date: 30.days.ago.to_date,
      name: "First manual recon valuation",
      amount: 1200,
      currency: "USD",
      entryable: Valuation.new(kind: "reconciliation")
    )

    manager = Account::CurrentBalanceManager.new(account)

    assert_equal 1, account.valuations.count

    # Here, we assume user is once again "overriding" the balance to 1400
    manager.set_current_balance(1400)

    today_valuation = account.entries.valuations.find_by(date: Date.current)

    assert_equal 2, account.valuations.count
    assert_equal 1400, today_valuation.amount

    assert_equal 1400, account.balance
  end

  test "all manual non cash accounts append reconciliations for current balance updates" do
    [ Property, Vehicle, OtherAsset, Loan, OtherLiability ].each do |account_type|
      account = @family.accounts.create!(
        name: "Test",
        balance: 1000,
        cash_balance: 1000,
        currency: "USD",
        accountable: account_type.new
      )

      manager = Account::CurrentBalanceManager.new(account)

      assert_equal 0, account.valuations.count

      manager.set_current_balance(1400)

      assert_equal 1, account.valuations.count

      today_valuation = account.entries.valuations.find_by(date: Date.current)

      assert_equal 1400, today_valuation.amount
      assert_equal 1400, account.balance
    end
  end

  # Fulas Bank: a manual current account or card with movements keeps a
  # running balance, as in Bilance. Updating its balance writes an «Ajuste de
  # saldo» movement for the difference today (Account::BalanceAdjuster)
  # instead of moving the opening balance or fixing today's balance, so the
  # history stays as it was and anything entered later keeps adding up.
  test "Fulas Bank: updating a current account with movements writes a balance adjustment for the difference" do
    account = @family.accounts.create!(
      name: "Test",
      balance: 900, # opening 1000 - expense 100
      cash_balance: 900,
      currency: "USD",
      accountable: Depository.new
    )

    account.entries.create!(
      date: 1.year.ago.to_date,
      name: "Test opening valuation",
      amount: 1000,
      currency: "USD",
      entryable: Valuation.new(kind: "opening_anchor")
    )

    account.entries.create!(
      date: 10.days.ago.to_date,
      name: "Test expense transaction",
      amount: 100,
      currency: "USD",
      entryable: Transaction.new
    )

    assert_difference "account.entries.count", 1 do
      Account::CurrentBalanceManager.new(account).set_current_balance(1000)
    end

    adjustment = Account::BalanceAdjuster.adjustments_for(account).sole
    assert_equal Date.current, adjustment.date
    assert_equal(-100, adjustment.amount, "money in raises an asset's balance")
    assert adjustment.excluded?, "an adjustment is neither income nor expense"
    assert_equal 1000, account.valuations.find_by(kind: "opening_anchor").entry.amount, "the opening balance is left alone"
    assert_empty account.valuations.reconciliation, "no fixed balance today"
    assert_equal 1000, account.balance
  end

  test "Fulas Bank: updating a credit card with movements writes a balance adjustment for the difference" do
    account = @family.accounts.create!(
      name: "Test",
      balance: 1100, # opening 1000 + expense 100 (expenses increase a card's balance)
      cash_balance: 1100,
      currency: "USD",
      accountable: CreditCard.new
    )

    account.entries.create!(
      date: 1.year.ago.to_date,
      name: "Test opening valuation",
      amount: 1000,
      currency: "USD",
      entryable: Valuation.new(kind: "opening_anchor")
    )

    account.entries.create!(
      date: 10.days.ago.to_date,
      name: "Test expense transaction",
      amount: 100,
      currency: "USD",
      entryable: Transaction.new
    )

    Account::CurrentBalanceManager.new(account).set_current_balance(1000)

    adjustment = Account::BalanceAdjuster.adjustments_for(account).sole
    assert_equal(-100, adjustment.amount, "lowering a debt is money in")
    assert_equal 1000, account.valuations.find_by(kind: "opening_anchor").entry.amount
    assert_equal 1000, account.balance
  end

  test "Fulas Bank: a current account with no movements yet just changes its opening balance" do
    account = @family.accounts.create!(
      name: "Test",
      balance: 1000,
      cash_balance: 1000,
      currency: "USD",
      accountable: Depository.new
    )

    account.entries.create!(
      date: 1.year.ago.to_date,
      name: "Test opening valuation",
      amount: 1000,
      currency: "USD",
      entryable: Valuation.new(kind: "opening_anchor")
    )

    assert_no_difference "account.entries.count" do
      Account::CurrentBalanceManager.new(account).set_current_balance(1200)
    end

    assert_equal 1200, account.valuations.find_by(kind: "opening_anchor").entry.amount
  end

  # -------------------------------------------------------------------------------------------------
  # Linked account current balance management
  #
  # Linked accounts manage "current balance" via the special `current_anchor` valuation.
  # This is NOT a user-facing feature, and is primarily used in "processors" while syncing
  # linked account data (e.g. via Plaid)
  # -------------------------------------------------------------------------------------------------

  test "when no existing anchor for linked account, creates new anchor" do
    manager = Account::CurrentBalanceManager.new(@linked_account)

    assert_difference -> { @linked_account.entries.count } => 1,
                     -> { @linked_account.valuations.count } => 1 do
      result = manager.set_current_balance(1000)

      assert result.success?
      assert result.changes_made?
      assert_nil result.error
    end

    current_anchor = @linked_account.valuations.current_anchor.first
    assert_not_nil current_anchor
    assert_equal 1000, current_anchor.entry.amount
    assert_equal "current_anchor", current_anchor.kind

    entry = current_anchor.entry
    assert_equal 1000, entry.amount
    assert_equal Date.current, entry.date
    assert_equal "Current balance", entry.name  # Depository type returns "Current balance"

    assert_equal 1000, @linked_account.balance
  end

  # A provider whose figures come from a statement knows the day they describe,
  # which is not always today.
  test "anchors a linked account balance on the date it is given" do
    manager = Account::CurrentBalanceManager.new(@linked_account)
    statement_date = Date.current - 1.day

    result = manager.set_current_balance(1000, date: statement_date)
    assert result.success?

    entry = @linked_account.valuations.current_anchor.first.entry
    assert_equal statement_date, entry.date
    assert_equal 1000, entry.amount
  end

  # A statement older than the anchor is a correction to a day gone by. It is
  # recorded on that day, and the newer anchor -- with the newer figure, and the
  # balance the account reports -- is left alone. This also covers an account
  # whose anchor is still dated by the day it was written: that anchor keeps its
  # date until a statement catches up with it, and is corrected in place then.
  test "a statement older than the anchor is recorded on its own date" do
    manager = Account::CurrentBalanceManager.new(@linked_account)
    manager.set_current_balance(2000)
    anchor_id = @linked_account.valuations.current_anchor.first.id

    manager.set_current_balance(1000, date: Date.current - 1.day)

    anchor = @linked_account.valuations.current_anchor.first
    assert_equal anchor_id, anchor.id, "the newer anchor must survive"
    assert_equal Date.current, anchor.entry.date
    assert_equal 2000, anchor.entry.amount
    assert_equal 2000, @linked_account.reload.balance, "the cached balance must not go backwards"

    older = @linked_account.entries.valuations.find_by(date: Date.current - 1.day)
    assert_not_nil older, "the older statement is kept where it belongs"
    assert_equal 1000, older.amount
  end

  # Two statements carrying the same date are one anchor, not an anchor and a
  # reconciliation sitting on the same day.
  test "a repeated statement date updates the anchor in place" do
    manager = Account::CurrentBalanceManager.new(@linked_account)
    statement_date = Date.current - 1.day
    manager.set_current_balance(1000, date: statement_date)

    travel_to Date.current + 1.day do
      assert_no_difference -> { @linked_account.valuations.count } do
        manager.set_current_balance(1500, date: statement_date)
      end
    end

    assert_equal 1, @linked_account.valuations.current_anchor.count
    entry = @linked_account.valuations.current_anchor.first.entry
    assert_equal statement_date, entry.date
    assert_equal 1500, entry.amount
  end

  test "preserves previous day anchor as reconciliation when updating linked account balance" do
    # First create a current anchor
    manager = Account::CurrentBalanceManager.new(@linked_account)
    result = manager.set_current_balance(1000)
    assert result.success?

    current_anchor = @linked_account.valuations.current_anchor.first
    original_id = current_anchor.id

    # Travel to tomorrow to ensure date change
    travel_to Date.current + 1.day do
      # Now update it
      assert_difference -> { @linked_account.entries.count } => 1,
                       -> { @linked_account.valuations.count } => 1 do
        result = manager.set_current_balance(2000)
        assert result.success?
        assert result.changes_made?
      end

      # The old anchor should now be a reconciliation
      preserved_valuation = Valuation.find(original_id)
      assert_equal "reconciliation", preserved_valuation.kind
      assert_equal 1000, preserved_valuation.entry.amount
      assert_equal Valuation.build_reconciliation_name(@linked_account.accountable_type), preserved_valuation.entry.name
      assert_equal Date.yesterday, preserved_valuation.entry.date

      # A new current anchor should exist for today
      new_anchor = @linked_account.valuations.current_anchor.first
      assert_not_equal original_id, new_anchor.id
      assert_equal 2000, new_anchor.entry.amount
      assert_equal Date.current, new_anchor.entry.date
    end

    assert_equal 2000, @linked_account.balance
  end

  test "does not preserve same-day anchor as reconciliation" do
    manager = Account::CurrentBalanceManager.new(@linked_account)

    # Create initial anchor
    result = manager.set_current_balance(1000)
    assert result.success?

    current_anchor = @linked_account.valuations.current_anchor.first
    original_id = current_anchor.id

    # Try to set the same value on the same date
    assert_no_difference -> { @linked_account.entries.count } do
      result = manager.set_current_balance(1000)
      assert result.success?
      assert_not result.changes_made?
    end

    # Update with different value on the same day
    assert_no_difference -> { @linked_account.entries.count } do
      assert_no_difference -> { @linked_account.valuations.count } do
        result = manager.set_current_balance(1500)
        assert result.success?
        assert result.changes_made?
      end
    end

    current_anchor.reload
    assert_equal original_id, current_anchor.id
    assert_equal 1500, current_anchor.entry.amount
    assert_equal "current_anchor", current_anchor.kind
    assert_equal Date.current, current_anchor.entry.date

    assert_equal 1500, @linked_account.balance
  end

  test "current_balance returns balance from current anchor" do
    manager = Account::CurrentBalanceManager.new(@linked_account)

    # Create a current anchor
    manager.set_current_balance(1500)

    # Should return the anchor's balance
    assert_equal 1500, manager.current_balance

    # Update the anchor
    manager.set_current_balance(2500)

    # Should return the updated balance
    assert_equal 2500, manager.current_balance

    assert_equal 2500, @linked_account.balance
  end

  test "current_balance falls back to account balance when no anchor exists" do
    manager = Account::CurrentBalanceManager.new(@linked_account)

    # When no current anchor exists, should fall back to account.balance
    assert_equal @linked_account.balance, manager.current_balance

    assert_equal @linked_account.balance, @linked_account.balance
  end
end
