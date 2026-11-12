require "test_helper"

class InvestmentsOverview::RealizedGainsTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @user = users(:empty)
    @account = @family.accounts.create!(name: "Cuenta de Valores", balance: 0, currency: "USD",
                                        accountable: Investment.new(subtype: "stocks"))
    @security = securities(:aapl)
  end

  test "a sale's gain by average cost and by FIFO, the first shares bought being the first sold" do
    trade(Date.new(2025, 2, 20), qty: 100, price: 5)
    trade(Date.new(2026, 2, 20), qty: 100, price: 7)
    trade(Date.new(2026, 6, 1), qty: -100, price: 10)

    realized = InvestmentsOverview::RealizedGains.new(@family, user: @user, year: 2026, today: Date.new(2026, 10, 19))

    sale = realized.sales.sole
    assert_equal 100, sale.qty
    assert_equal 1_000, sale.proceeds
    assert_equal 500, sale.fifo_gain, "the 2025 shares, bought at 5"
    assert_equal 400, sale.average_gain, "at the average of 6"
    assert_equal Money.new(500, "USD"), realized.fifo_total
    assert_equal [ 2026 ], realized.years
  end

  test "Fulas Bank: what the shares still held cost by FIFO, and everything the sales gained" do
    trade(Date.new(2024, 2, 20), qty: 100, price: 5)
    trade(Date.new(2025, 2, 20), qty: 100, price: 7)
    trade(Date.new(2025, 6, 1), qty: -50, price: 10)
    trade(Date.new(2026, 6, 1), qty: -100, price: 12)

    realized = InvestmentsOverview::RealizedGains.new(@family, user: @user, year: 2026, today: Date.new(2026, 10, 19))

    assert_equal 350, realized.open_cost(@account), "50 shares of the 2025 lot, at 7"
    assert_equal 250 + 600, realized.realized_for(@account), "50 × (10 − 5) in 2025, then 50 × (12 − 5) + 50 × (12 − 7)"
  end

  test "Fulas Bank: an account without trades has no cost nor sales" do
    assert_nil InvestmentsOverview::RealizedGains.new(@family, user: @user).open_cost(@account)
    assert_nil InvestmentsOverview::RealizedGains.new(@family, user: @user).realized_for(@account)
  end

  test "no sales in the year" do
    trade(Date.new(2026, 2, 20), qty: 10, price: 5)

    assert_not InvestmentsOverview::RealizedGains.new(@family, user: @user, year: 2026).any?
  end

  private
    def trade(date, qty:, price:)
      @account.entries.create!(date: date, amount: qty * price, currency: "USD", name: "Trade",
                               entryable: Trade.new(qty: qty, price: price, fee: 0, currency: "USD", security: @security))
    end
end
