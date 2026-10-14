require "test_helper"

class Transaction::PanelTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @user = users(:empty)
    @checking = @family.accounts.create!(name: "Panel checking", balance: 1_000, currency: "USD", accountable: Depository.new)
    @card = @family.accounts.create!(name: "Panel card", balance: 200, currency: "USD", accountable: CreditCard.new)
    @today = Date.new(2026, 10, 14) # a Wednesday
  end

  test "shows the current accounts until the user chooses" do
    assert_equal [ @checking ], panel.accounts

    @user.update_transactions_panel_account_ids!([ @card.id ])
    assert_equal [ @card ], panel.accounts
    assert_equal Money.new(-200, "USD"), panel.accounts_total

    @user.update_transactions_panel_account_ids!([])
    assert_empty panel.accounts
  end

  test "three weeks from Monday two weeks ago, each day split by main category" do
    food = @family.categories.create!(name: "Comida", color: "#22c55e")
    market = @family.categories.create!(name: "Súper", color: "#16a34a", parent: food)
    fun = @family.categories.create!(name: "Ocio", color: "#3b82f6")

    create_transaction(account: @checking, amount: 30, date: Date.new(2026, 10, 13), category: market)
    create_transaction(account: @checking, amount: 20, date: Date.new(2026, 10, 13), category: food)
    create_transaction(account: @checking, amount: 15, date: Date.new(2026, 10, 13), category: fun)
    create_transaction(account: @checking, amount: -900, date: Date.new(2026, 10, 13))
    create_transaction(account: @checking, amount: 500, date: Date.new(2026, 10, 13), kind: "funds_movement")
    create_transaction(account: @card, amount: 40, date: Date.new(2026, 9, 28))

    weeks = panel.weeks

    assert_equal [ Date.new(2026, 9, 28), Date.new(2026, 10, 5), Date.new(2026, 10, 12) ], weeks.map(&:start_date)
    assert_equal 7, weeks.last.days.size

    tuesday = weeks.last.days.find { |day| day.date == Date.new(2026, 10, 13) }
    assert_equal [ [ "Comida", 50 ], [ "Ocio", 15 ] ], tuesday.segments.map { |segment| [ segment.name, segment.amount.to_i ] }
    assert_equal 65, weeks.last.total.to_i
    assert_equal 40, weeks.first.total.to_i
    assert_equal 65, panel.max_day_total.to_i
  end

  private
    def panel
      Transaction::Panel.new(@family, user: @user.reload, today: @today)
    end
end
