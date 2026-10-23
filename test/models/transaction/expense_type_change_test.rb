require "test_helper"

class Transaction::ExpenseTypeChangeTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = Account.create!(family: @family, owner: users(:family_admin), name: "Type checking", balance: 1_000,
                               currency: "USD", accountable: Depository.new, status: "active")
    travel_to Date.new(2026, 10, 14)
  end

  test "a movement with no series is variable until marked otherwise" do
    entry = create_transaction(account: @account, name: "Mercadona", amount: 60, date: Date.new(2026, 10, 2))

    assert_equal "variable", entry.transaction.effective_expense_type
    assert_not entry.transaction.expense_type_chosen?

    assert_no_difference -> { @family.recurring_transactions.count } do
      assert change(entry, "variable").save
    end
    assert_equal "variable", entry.transaction.reload.expense_type
  end

  test "a movement paid by a series is fixed unless marked otherwise" do
    entry = create_transaction(account: @account, name: "Netflix", amount: 15.99, date: Date.new(2026, 10, 5))
    series = recurring_transactions(:netflix_subscription)
    occurrence = series.recurring_occurrences.create!(family: @family, original_due_on: Date.new(2026, 10, 6), due_on: Date.new(2026, 10, 6), currency: "USD")
    occurrence.allocations.create!(entry: entry, allocated_amount: 15.99, currency: "USD", source: "user_created")

    transaction = Transaction.find(entry.entryable_id)
    assert_equal series, transaction.recurring_series
    assert_equal "fixed", transaction.effective_expense_type
  end

  test "marking it fixed creates a series that never ends" do
    entry = create_transaction(account: @account, name: "Alquiler trastero", amount: 90, date: Date.new(2026, 10, 10))

    assert_difference -> { @family.recurring_transactions.count } => 1 do
      assert change(entry, "fixed").save
    end

    transaction = Transaction.find(entry.entryable_id)
    assert_equal "fixed", transaction.expense_type
    assert transaction.recurring_series.ends_never?
    assert transaction.recurring_series.active?
  end

  test "marking it recurring with a number of payments ends the series on the last of them" do
    entry = create_transaction(account: @account, name: "Préstamo sofá", amount: 120, date: Date.new(2026, 10, 10))

    assert change(entry, "recurring", periods: "3").save

    series = Transaction.find(entry.entryable_id).recurring_series
    assert series.ends_on_date?
    assert_equal Date.new(2027, 1, 10), series.end_on
  end

  test "marking it recurring with a date ends the series then, and fixed takes the end away" do
    entry = create_transaction(account: @account, name: "Curso inglés", amount: 75, date: Date.new(2026, 10, 10))

    assert change(entry, "recurring", end_on: "2027-06-30").save
    series = Transaction.find(entry.entryable_id).recurring_series
    assert_equal Date.new(2027, 6, 30), series.end_on

    # Fixed again keeps the end unless told it never ends.
    assert change(entry, "fixed").save
    assert_equal Date.new(2027, 6, 30), series.reload.end_on

    assert change(entry, "fixed", never_ends: true).save
    assert series.reload.ends_never?
    assert_nil series.end_on
  end

  # Fulas Bank: a bill or a subscription is the kind of its series; neither
  # ends, they are switched off instead.
  test "marking it a bill or a subscription gives its series that kind" do
    entry = create_transaction(account: @account, name: "Iberdrola", amount: 64, date: Date.new(2026, 10, 10))

    assert change(entry, "bill").save
    transaction = Transaction.find(entry.entryable_id)
    assert_equal "fixed", transaction.expense_type
    assert_equal "bill", transaction.recurring_series.fulas_kind
    assert_equal "bill", Transaction::ExpenseTypeChange.current_choice(transaction)

    assert change(entry, "subscription", end_on: "2027-01-31").save
    series = Transaction.find(entry.entryable_id).recurring_series
    assert series.typed_subscription?
    assert series.ends_never?
  end

  test "recurring needs an end" do
    entry = create_transaction(account: @account, name: "Curso", amount: 75, date: Date.new(2026, 10, 10))
    result = change(entry, "recurring")

    assert_not result.save
    assert_equal :end_required, result.error
    assert_nil entry.transaction.reload.expense_type
  end

  test "rejects unknown types" do
    entry = create_transaction(account: @account, name: "Algo", amount: 10, date: Date.new(2026, 10, 10))
    result = change(entry, "weekly")

    assert_not result.save
    assert_equal :invalid_type, result.error
  end

  private
    def change(entry, type, **options)
      Transaction::ExpenseTypeChange.new(Transaction.find(entry.entryable_id), expense_type: type, **options)
    end
end
