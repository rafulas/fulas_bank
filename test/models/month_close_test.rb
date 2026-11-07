require "test_helper"

class MonthCloseTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @user = users(:empty)
    @today = Date.new(2026, 11, 4)
    @checking = @family.accounts.create!(name: "Cuenta", owner: @user, balance: 0, currency: "USD", accountable: Depository.new)
    @fund = @family.accounts.create!(name: "Fondo", owner: @user, balance: 1_000, currency: "USD", accountable: Investment.new)
  end

  test "lists what is still to do in the month just ended" do
    create_transaction(account: @checking, amount: 20, date: Date.new(2026, 10, 10))
    @fund.entries.create!(name: "Saldo", date: Date.new(2026, 9, 30), amount: 1_000, currency: "USD", entryable: Valuation.new)

    close = month_close

    assert_equal "2026-10", close.to_param
    assert_equal [ @checking ], step(close, :statements).items.map(&:account)
    assert_equal [ @fund ], step(close, :balances).items.map(&:account)
    assert_equal 1, step(close, :categorize).count
    assert_not close.done?
    assert close.offer_on_inicio?
  end

  test "ticks the steps once the data is there" do
    category = @family.categories.create!(name: "Comida", color: "#22c55e")
    create_transaction(account: @checking, amount: 20, date: Date.new(2026, 10, 29), category: category)
    @fund.entries.create!(name: "Saldo", date: Date.new(2026, 10, 31), amount: 1_100, currency: "USD", entryable: Valuation.new)

    close = month_close

    assert step(close, :statements).done?
    assert step(close, :balances).done?
    assert step(close, :categorize).done?
    assert close.done?
    assert_not close.offer_on_inicio?
  end

  test "an account that never had a movement is left alone" do
    @fund.entries.create!(name: "Saldo", date: Date.new(2026, 10, 31), amount: 1_100, currency: "USD", entryable: Valuation.new)

    assert step(month_close, :statements).done?
  end

  test "is no longer offered on Inicio after the first days" do
    create_transaction(account: @checking, amount: 20, date: Date.new(2026, 10, 10))

    assert_not MonthClose.latest(@family, user: @user, today: Date.new(2026, 11, 20)).offer_on_inicio?
  end

  test "only months close" do
    assert_raises(ArgumentError) do
      MonthClose.new(Recap.for(@family, user: @user, kind: "week", date: @today, today: @today))
    end
  end

  private
    def month_close
      MonthClose.latest(@family, user: @user, today: @today)
    end

    def step(close, key)
      close.steps.find { |candidate| candidate.key == key }
    end
end
