require "test_helper"

class SavingsFlowTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @checking = accounts(:depository)
    @broker = accounts(:investment)
    @period = Period.custom(start_date: 10.days.ago.to_date, end_date: Date.current)
  end

  test "money sent to investment accounts, net of what came back, and its share of income" do
    create_transfer(from_account: @checking, to_account: @broker, amount: 500, date: 2.days.ago.to_date)
    create_transfer(from_account: @broker, to_account: @checking, amount: 100, date: 1.day.ago.to_date)
    create_transfer(from_account: @checking, to_account: @broker, amount: 900, date: 40.days.ago.to_date)

    flow = SavingsFlow.new(@family, user: @user, period: @period, income: Money.new(2_000, "USD"))

    assert flow.any_saving_accounts?
    assert_equal Money.new(500, "USD"), flow.saved
    assert_equal Money.new(100, "USD"), flow.withdrawn
    assert_equal Money.new(400, "USD"), flow.net
    assert_equal 20.0, flow.share_of_income
  end

  test "no income, no share" do
    flow = SavingsFlow.new(@family, user: @user, period: @period, income: Money.new(0, "USD"))

    assert_nil flow.share_of_income
  end
end
