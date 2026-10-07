require "test_helper"

class Loan::PaymentLinkTest < ActiveSupport::TestCase
  include EntriesTestHelper

  # 12,000 at 0% over 12 months from 1 January: 1,000 a month from 1
  # February, so after the March instalment (the second) 10,000 is still owed.
  setup do
    @loan_account = accounts(:loan)
    @loan = @loan_account.loan
    @loan.update!(interest_rate: 0, rate_type: "fixed", term_months: 12, initial_balance: 12_000,
                  start_date: Date.new(2026, 1, 1))
  end

  test "linking a movement records it and anchors the loan at the schedule's balance" do
    entry = create_transaction(account: accounts(:depository), amount: 1_000, date: Date.new(2026, 3, 1), name: "Cuota hipoteca")

    link = @loan.link_payment!(entry)

    assert_equal entry, link.entry
    assert_equal BigDecimal("1000"), link.scheduled_payment.payment.amount
    valuation = @loan_account.entries.find_by(entryable_type: "Valuation", date: Date.new(2026, 3, 1))
    assert_not_nil valuation, "the loan is anchored on the payment date"
    assert_equal BigDecimal("10000"), valuation.amount
    assert_equal accounts(:depository), entry.reload.account, "the movement stays where it was paid from"
  end

  test "a movement can pay only one loan, and only an outgoing one" do
    entry = create_transaction(account: accounts(:depository), amount: 1_000, date: Date.new(2026, 3, 1))
    @loan.link_payment!(entry)

    assert_raises(ActiveRecord::RecordInvalid) { @loan.link_payment!(entry) }

    income = create_transaction(account: accounts(:depository), amount: -1_000, date: Date.new(2026, 4, 1))
    assert_raises(ActiveRecord::RecordInvalid) { @loan.link_payment!(income) }
  end

  test "candidates are unlinked charges close to the instalment" do
    close = create_transaction(account: accounts(:depository), amount: 1_010, date: Date.new(2026, 4, 1))
    far = create_transaction(account: accounts(:depository), amount: 40, date: Date.new(2026, 4, 2))
    linked = create_transaction(account: accounts(:depository), amount: 1_000, date: Date.new(2026, 3, 1))
    before_origination = create_transaction(account: accounts(:depository), amount: 1_000, date: Date.new(2025, 12, 1))
    @loan.link_payment!(linked)

    candidates = @loan.payment_candidates

    assert_includes candidates, close
    assert_not_includes candidates, far
    assert_not_includes candidates, linked
    assert_not_includes candidates, before_origination
  end
end
