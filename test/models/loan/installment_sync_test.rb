require "test_helper"

class Loan::InstallmentSyncTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @checking = @family.accounts.create!(name: "Cuenta nómina", balance: 3_000, currency: "EUR", accountable: Depository.new)
    @loan_account = @family.accounts.create!(
      name: "Préstamo coche", balance: 9_000, currency: "EUR",
      accountable: Loan.new(payment_amount: 300, payment_day: 5, start_date: Date.new(2026, 1, 5), term_months: 36)
    )
    @today = Date.new(2026, 10, 18)
  end

  test "a loan with an instalment gets its own recurring movement, kept in step" do
    series = sync.sync_account(@loan_account)
    assert_equal series, @family.recurring_transactions.find_by(loan_account: @loan_account), "saving the loan already made it"

    assert series.persisted?
    assert_equal @loan_account, series.loan_account
    assert_equal @checking, series.account
    assert_equal "Préstamo coche", series.name
    assert series.typed_installment?
    assert_equal 300, series.amount
    assert_equal 5, series.expected_day_of_month
    assert_equal "on_date", series.end_mode
    assert_equal Date.new(2028, 12, 5), series.end_on

    @loan_account.accountable.update_columns(payment_amount: 320, payment_day: 10)
    @loan_account.reload
    sync.sync_account(@loan_account)

    assert_equal 1, @family.recurring_transactions.where(loan_account: @loan_account).count
    assert_equal 320, series.reload.amount
    assert_equal 10, series.expected_day_of_month
  end

  test "a recurring the user already made for it is adopted, not duplicated" do
    @family.recurring_transactions.where(loan_account: @loan_account).destroy_all
    mine = @family.recurring_transactions.create!(
      account: @checking, name: "Cuota coche", amount: 301, currency: "EUR", expected_day_of_month: 5,
      status: "active", manual: true, bill_type: "installment",
      last_occurrence_date: Date.new(2026, 9, 5), next_expected_date: Date.new(2026, 10, 5)
    )

    assert_equal mine, sync.sync_account(@loan_account)
    assert_equal 1, @family.recurring_transactions.count
    assert_equal "Cuota coche", mine.reload.name
    assert_equal @loan_account.id, mine.loan_account_id
  end

  test "a paid-off loan ends its movement" do
    series = sync.sync_account(@loan_account)
    @loan_account.accountable.update_columns(payment_amount: nil)
    @loan_account.reload

    sync.sync_account(@loan_account)
    assert series.reload.ended?
  end

  test "a loan paid twice, by its own movement and one from the bank, keeps the bank's and ends the other" do
    own = sync.sync_account(@loan_account)
    bank = @family.recurring_transactions.create!(
      account: @checking, name: "Amortización préstamo", amount: 300, currency: "EUR", expected_day_of_month: 3,
      status: "active", manual: false, bill_type: "bill",
      last_occurrence_date: Date.new(2026, 10, 3), next_expected_date: Date.new(2026, 11, 3)
    )
    charge = @checking.entries.create!(date: Date.new(2026, 10, 3), amount: 300, currency: "EUR", name: "Amortización préstamo",
                                       entryable: Transaction.new)
    occurrence = bank.recurring_occurrences.find_or_initialize_by(original_due_on: charge.date)
    occurrence.update!(family: @family, currency: "EUR", due_on: charge.date, expected_amount: 300,
                       status: "paid", closed_at: Time.current, closed_source: "user")
    RecurringAllocation.create!(recurring_occurrence: occurrence, entry: charge, allocated_amount: 300, currency: "EUR",
                                source: "user_confirmed", paid_on: charge.date)

    kept = sync.sync_account(@loan_account)

    assert_equal bank, kept
    assert_equal @loan_account.id, bank.reload.loan_account_id
    assert bank.typed_installment?
    assert_equal 3, bank.expected_day_of_month, "keeps the day the bank charges it"
    assert own.reload.ended?
    assert_nil own.loan_account_id
    assert_equal bank.id, own.replaced_by_id
    assert_equal [ bank ], @family.recurring_transactions.active.to_a
  end

  test "a twin with no bank charges matched ends, and the loan's own movement stays" do
    own = sync.sync_account(@loan_account)
    twin = @family.recurring_transactions.create!(
      account: @checking, name: "Pago préstamo coche", amount: 300, currency: "EUR", expected_day_of_month: 7,
      status: "active", manual: true, bill_type: "bill",
      last_occurrence_date: Date.new(2026, 10, 7), next_expected_date: Date.new(2026, 11, 7)
    )

    assert_equal own, sync.sync_account(@loan_account)
    assert twin.reload.ended?
    assert own.reload.active?
    assert_equal 5, own.expected_day_of_month
  end

  test "a payment of another amount is not taken for the loan" do
    sync.sync_account(@loan_account)
    other = @family.recurring_transactions.create!(
      account: @checking, name: "Alquiler trastero", amount: 400, currency: "EUR", expected_day_of_month: 5,
      status: "active", manual: true, bill_type: "bill",
      last_occurrence_date: Date.new(2026, 10, 5), next_expected_date: Date.new(2026, 11, 5)
    )

    sync.sync_account(@loan_account)
    assert other.reload.active?
    assert_nil other.loan_account_id
  end

  private
    def sync
      Loan::InstallmentSync.new(@family, today: @today)
    end
end
