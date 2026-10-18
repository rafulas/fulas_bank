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

  private
    def sync
      Loan::InstallmentSync.new(@family, today: @today)
    end
end
