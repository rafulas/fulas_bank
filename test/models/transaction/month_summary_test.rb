require "test_helper"

class Transaction::MonthSummaryTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @user = users(:empty)
    @account = @family.accounts.create!(name: "Summary checking", balance: 0, currency: "USD", accountable: Depository.new)
    @month = Date.new(2026, 5, 1)
  end

  test "spent, earned and what the month saved" do
    create_transaction(account: @account, amount: 600, date: Date.new(2026, 5, 3))
    create_transaction(account: @account, amount: -2_000, date: Date.new(2026, 5, 28))
    create_transaction(account: @account, amount: 300, date: Date.new(2026, 5, 10), kind: "funds_movement")
    create_transaction(account: @account, amount: 999, date: Date.new(2026, 6, 1))
    excluded = create_transaction(account: @account, amount: 50, date: Date.new(2026, 5, 4))
    excluded.update!(excluded: true)

    summary = build_summary

    assert_equal Money.new(600, "USD"), summary.spent
    assert_equal Money.new(2_000, "USD"), summary.income
    assert_equal Money.new(1_400, "USD"), summary.net
    assert_equal 70, summary.savings_rate
  end

  test "no savings when the month cost more than it earned" do
    create_transaction(account: @account, amount: 900, date: Date.new(2026, 5, 3))
    create_transaction(account: @account, amount: -500, date: Date.new(2026, 5, 28))

    assert_equal 0, build_summary.savings_rate
    assert_equal 0, build_summary(month: Date.new(2026, 7, 1)).savings_rate
  end

  test "follows the list's filters" do
    other = @family.accounts.create!(name: "Other", balance: 0, currency: "USD", accountable: Depository.new)
    create_transaction(account: @account, amount: 100, date: Date.new(2026, 5, 3))
    create_transaction(account: other, amount: 700, date: Date.new(2026, 5, 3))

    search = Transaction::Search.new(@family, filters: { "account_ids" => [ @account.id ] })
    summary = Transaction::MonthSummary.new(@family, month: @month, scope: search.transactions_scope, user: @user)

    assert_equal Money.new(100, "USD"), summary.spent
  end

  test "no budget, no budget difference" do
    assert_nil build_summary.budget_difference
    assert_not build_summary.over_budget?
  end

  private
    def build_summary(month: @month)
      Transaction::MonthSummary.new(@family, month: month, scope: Transaction::Search.new(@family).transactions_scope, user: @user)
    end
end
