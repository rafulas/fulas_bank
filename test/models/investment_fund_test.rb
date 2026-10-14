require "test_helper"

class InvestmentFundTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:investment)
  end

  test "is worth its units times its price, and gains over what was put in" do
    fund = @family.investment_funds.new(account: @account, name: "Indexado", units: "120.5", price: "12.3456", price_date: Date.current, cost: 1_200)

    assert_equal Money.new(BigDecimal("1487.6448"), @account.currency), fund.value
    assert_in_delta 287.64, fund.gain.amount, 0.01
    assert_in_delta 0.2397, fund.return_ratio, 0.0001
    assert_not fund.stale?
    fund.price_date = Date.current - 8
    assert fund.stale?
  end

  test "saving keeps the price in the history and sets the account to what its funds are worth" do
    fund = @family.investment_funds.new

    assert_difference -> { @account.entries.where(entryable_type: "Valuation").count } => 1 do
      assert fund.apply(account: @account, name: "Indexado", units: 100, price: 10, price_date: Date.current)
    end

    assert_equal [ [ Date.current, BigDecimal("10") ] ], fund.prices.map { |price| [ price.date, price.price ] }
    assert_equal BigDecimal("1000"), @account.entries.where(entryable_type: "Valuation", date: Date.current).sole.amount
  end

  test "an older price goes to the history without replacing the current one" do
    fund = @family.investment_funds.create!(account: @account, name: "Indexado", units: 100, price: 10, price_date: Date.current)

    fund.record_price!(9, date: Date.current - 10)
    assert_equal BigDecimal("10"), fund.reload.price

    fund.record_price!(11, date: Date.current)
    assert_equal [ BigDecimal("11"), Date.current ], [ fund.reload.price, fund.price_date ]
    assert_equal 2, fund.prices.count
  end

  test "only in an investment account of the family" do
    fund = @family.investment_funds.new(account: accounts(:depository), name: "Mal", units: 1)

    assert_not fund.valid?
    assert fund.errors.key?(:account)
  end
end
