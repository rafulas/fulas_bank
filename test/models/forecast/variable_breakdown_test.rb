require "test_helper"

class Forecast::VariableBreakdownTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @today = Date.new(2026, 10, 14)
    @account = Account.create!(family: @family, owner: users(:family_admin), name: "Breakdown checking", balance: 1_000,
                               currency: "USD", accountable: Depository.new, status: "active")
    @food = @family.categories.create!(name: "Comida breakdown", color: "#000000")
  end

  test "shows the months averaged, flags the highest and the lowest, and gives the same result" do
    spend(100, Date.new(2026, 7, 5), category: @food)
    spend(300, Date.new(2026, 8, 5), category: @food)
    spend(900, Date.new(2026, 9, 5))

    samples = breakdown.samples.index_by(&:month)
    # 100, 300, 900: the lowest and the highest are dropped, 300 is kept.
    assert samples[Date.new(2026, 7, 1)].dropped
    assert_not samples[Date.new(2026, 8, 1)].dropped
    assert samples[Date.new(2026, 9, 1)].dropped
    assert_equal 900, samples[Date.new(2026, 9, 1)].total
    assert_equal Forecast::VariableEstimate.new(@family, accounts: [ @account ], today: @today).combined_monthly(Date.new(2026, 11, 1)),
                 breakdown.monthly
  end

  test "splits the spending by category, the heaviest first, with each one's movements" do
    spend(100, Date.new(2026, 8, 5), category: @food)
    spend(50, Date.new(2026, 9, 5), category: @food)
    spend(900, Date.new(2026, 9, 6))

    rows = breakdown.categories
    assert_equal [ Forecast::VariableBreakdown::NONE, @food.id ], rows.map(&:key)
    assert_equal 100, rows.last.totals[Date.new(2026, 8, 1)]

    entries = breakdown.entries_for(@food.id)
    assert_equal [ 50 ], entries[Date.new(2026, 9, 1)].map(&:amount)
    assert_equal [ 900 ], breakdown.entries_for(Forecast::VariableBreakdown::NONE)[Date.new(2026, 9, 1)].map(&:amount)
  end

  private
    def breakdown
      Forecast::VariableBreakdown.new(@family, accounts: [ @account ], month: Date.new(2026, 11, 1), today: @today)
    end

    def spend(amount, date, **attributes)
      create_transaction(account: @account, name: "Gasto", amount: amount, date: date, **attributes)
    end
end
