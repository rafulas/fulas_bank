require "test_helper"

class StockPlanTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @investment = accounts(:investment)
    @cash = accounts(:depository)
    # AAPL's latest price in the fixtures is 215 USD.
    @plan = @family.stock_plans.create!(name: "Bonus", investment_account: @investment, security: securities(:aapl), cash_account: @cash,
                                        base_bonus: 20_000, stock_percent: 28, tax_percent: 30, gift_every: 10, lock_years: 3)
  end

  test "a coming year is estimated from the bonus and the latest price, with the free shares" do
    grant = @plan.grants.create!(granted_on: Date.current + 20, achievement_percent: 100, stock_percent: 28)

    assert_equal BigDecimal("5600"), grant.stock_amount
    assert_equal BigDecimal("10080"), grant.net_cash # (20.000 − 5.600) − 30 % IRPF
    assert_equal :estimated, grant.shares_source
    assert_equal 26, grant.bought_shares # 5.600 / 215, rounded down
    assert_equal 2, grant.free_shares
    assert_equal 28, grant.total_shares
    assert_equal BigDecimal("6020"), grant.value
    assert_equal grant.granted_on + 3.years, grant.sell_on
  end

  test "a bigger bonus means more shares, and the real ones replace the estimate once typed" do
    grant = @plan.grants.create!(granted_on: Date.current + 20, achievement_percent: 120, stock_percent: 28)

    assert_equal BigDecimal("24000"), grant.gross_bonus
    assert_equal 34, grant.total_shares # 31 + 3

    grant.update!(shares: 30)

    assert_equal :typed, grant.shares_source
    assert_equal 33, grant.total_shares
  end

  test "a past year takes its shares from the purchases in the investment account" do
    granted_on = Date.current - 3.years + 10.days
    create_trade(securities(:aapl), account: @investment, qty: 50, date: granted_on, price: 100)
    grant = @plan.grants.create!(granted_on: granted_on, achievement_percent: 100, stock_percent: 28)

    assert_equal :traded, grant.shares_source
    assert_equal 50, grant.total_shares
    assert_equal BigDecimal("10750"), grant.value
    assert_equal Date.current + 10, grant.sell_on
  end

  test "the forecast expects the bonus cash and the shares on delivery, and their sale" do
    @plan.grants.create!(granted_on: Date.current + 20, achievement_percent: 100, stock_percent: 28)
    past = Date.current - 3.years + 10.days
    create_trade(securities(:aapl), account: @investment, qty: 50, date: past, price: 100)
    @plan.grants.create!(granted_on: past, achievement_percent: 100, stock_percent: 28)

    forecast = Forecast.new(@family, accounts: [ @cash, @investment ], main_account: @cash, through: Date.current + 30, include_variable: false)
    lines = forecast.flows.select { |flow| flow.source == :stock_plan }.map { |flow| [ flow.date, flow.account, flow.amount ] }

    assert_equal [
      [ Date.current + 10, @investment, BigDecimal("10750") ],
      [ Date.current + 10, @cash, BigDecimal("-10750") ],
      [ Date.current + 20, @cash, BigDecimal("-10080") ],
      [ Date.current + 20, @investment, BigDecimal("-6020") ]
    ].sort_by { |date, account, _| [ date, account.id ] }, lines.sort_by { |date, account, _| [ date, account.id ] }
  end
end
