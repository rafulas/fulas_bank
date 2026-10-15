require "test_helper"

class Category::FixedVariableTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "BBVA", balance: 0, currency: @family.currency, accountable: Depository.new)
    @today = Date.new(2026, 10, 15)
  end

  test "splits each month's spending into fixed, recurring and variable" do
    spend(700, Date.new(2026, 9, 1), expense_type: "fixed")
    spend(100, Date.new(2026, 9, 5), expense_type: "recurring")
    spend(200, Date.new(2026, 9, 10))
    spend(-50, Date.new(2026, 9, 12)) # a refund does not count

    september = result.months.find { |month| month.month == Date.new(2026, 9, 1) }

    assert_equal [ 700, 100, 200 ], [ september.fixed, september.recurring, september.variable ]
    assert_equal 80, september.committed_share
    assert_equal 12, result.months.size
    assert_equal Date.new(2026, 10, 1), result.months.last.month
  end

  private
    def result
      Category::FixedVariable.new(@family, account_ids: [ @account.id ], today: @today)
    end

    def spend(amount, date, expense_type: nil)
      create_transaction(account: @account, amount: amount, date: date, expense_type: expense_type, currency: @family.currency)
    end
end
