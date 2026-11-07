require "test_helper"

class PriceRisesTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @series = recurring_transactions(:netflix_subscription)
  end

  test "lists recent rises of active series with what they add over a year" do
    change = record(previous: 13.99, new: 15.99, on: 10.days.ago.to_date)

    rise = rises.sole

    assert_equal change, rise.change
    assert_equal BigDecimal("2"), rise.current - rise.previous
    assert_in_delta 14.3, rise.percent.to_f, 0.1
    assert_in_delta 24, rise.annual_extra.to_f, 0.5
  end

  test "leaves out drops, old changes and other series' states" do
    record(previous: 17.99, new: 15.99, on: 5.days.ago.to_date)
    record(previous: 12.99, new: 13.99, on: 100.days.ago.to_date)
    record(previous: 8.99, new: 9.99, on: 5.days.ago.to_date, series: recurring_transactions(:inactive_subscription))

    assert_empty rises
  end

  test "a dismissed rise is not shown again" do
    change = record(previous: 13.99, new: 15.99, on: 3.days.ago.to_date)

    PriceRises.dismiss!(@user, change.id)

    assert_empty PriceRises.new(@family, user: @user.reload).rises
  end

  private
    def rises
      PriceRises.new(@family, user: @user).rises
    end

    def record(previous:, new:, on:, series: @series)
      series.recurring_price_changes.create!(previous_amount: previous, new_amount: new, effective_on: on, currency: "USD", source: "detected")
    end
end
