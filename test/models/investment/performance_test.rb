require "test_helper"

class Investment::PerformanceTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @today = Date.new(2026, 10, 13)
    @account = @family.accounts.create!(name: "Póliza de ahorro", balance: 20_000, currency: "EUR",
                                        accountable: Investment.new(subtype: "savings_insurance"))
  end

  test "this year's gain is the value change minus what was put in" do
    balance(Date.new(2025, 12, 31), 15_000)
    balance(Date.new(2026, 4, 10), 16_400)
    balance(Date.new(2026, 10, 13), 20_000)
    contribute(1_000, Date.new(2026, 4, 10))
    contribute(2_000, Date.new(2026, 10, 13))

    ytd = performance.year_to_date

    assert_equal Money.new(3_000, "EUR"), ytd.contributed
    assert_equal Money.new(2_000, "EUR"), ytd.gain
    assert_equal Money.new(20_000, "EUR"), ytd.value
  end

  test "the return weights each contribution by how long it was invested" do
    balance(Date.new(2025, 12, 31), 10_000)
    balance(Date.new(2026, 7, 2), 16_000)
    balance(Date.new(2026, 12, 31), 16_500)
    contribute(5_000, Date.new(2026, 7, 2))

    summary = performance(today: Date.new(2026, 12, 31)).summary(Date.new(2026, 1, 1)..Date.new(2026, 12, 31))

    # Gain 16_500 − 10_000 − 5_000 = 1_500; the 5_000 was invested 182 of 365 days.
    assert_equal Money.new(1_500, "EUR"), summary.gain
    assert_in_delta 1_500.0 / (10_000 + 5_000 * 182 / 365.0), summary.return_ratio, 0.0001
  end

  test "lists the latest money movements and shows nothing without history" do
    assert_not performance.any?
    assert_nil performance.year_to_date

    contribute(179.27, Date.new(2026, 9, 22))

    assert_equal [ "Aportación" ], performance.recent_movements.map(&:name)
  end

  private
    def performance(today: @today)
      Investment::Performance.new(@account, today: today)
    end

    def balance(date, amount)
      @account.balances.create!(date: date, balance: amount, start_cash_balance: amount, currency: "EUR")
    end

    def contribute(amount, date)
      create_transaction(account: @account, name: "Aportación", amount: -amount, date: date, currency: "EUR")
    end
end
