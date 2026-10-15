require "test_helper"

class SubscriptionLinkTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @account = accounts(:depository)
    @music = subscription("Apple Music", 10.99)
    @icloud = subscription("iCloud 2 TB", 2.99)
  end

  test "moves a charge from one subscription to the other and remembers it" do
    charge = create_transaction(account: @account, name: "APPLE.COM/BILL", amount: 2.99, date: Date.current - 3)
    SubscriptionLink.new(charge).link!(@music)
    assert_equal @music, SubscriptionLink.new(charge.reload).current

    SubscriptionLink.new(charge.reload).link!(@icloud)

    assert_equal @icloud, SubscriptionLink.new(charge.reload).current
    assert RecurringMatchRejection.exists?(recurring_transaction: @music, entry: charge), "Apple Music will not take it back"
  end

  test "unlinks a charge" do
    charge = create_transaction(account: @account, name: "APPLE.COM/BILL", amount: 10.99, date: Date.current - 3)
    SubscriptionLink.new(charge).link!(@music)

    SubscriptionLink.new(charge.reload).link!(nil)

    assert_nil SubscriptionLink.new(charge.reload).current
  end

  test "makes a new subscription from a charge" do
    charge = create_transaction(account: @account, name: "DISNEY PLUS", amount: 8.99, date: Date.current - 2)

    series = SubscriptionLink.new(charge).create!(name: "Disney+")

    assert series.typed_subscription?
    assert_equal "Disney+", series.display_name
    assert_equal series, SubscriptionLink.new(charge.reload).current
  end

  test "the page adds them up a month, a year and in five years, and what dropping one saves" do
    SubscriptionsOverview.toggle_could_drop!(@user, @music.id, true)

    overview = SubscriptionsOverview.new(@family, user: @user.reload)
    ours = overview.rows.select { |row| [ @music, @icloud ].include?(row.series) }

    assert_equal 2, ours.size
    assert ours.find { |row| row.series == @music }.could_drop
    assert_equal overview.monthly * 12, overview.yearly
    assert_equal overview.yearly * 5, overview.five_years
    assert_in_delta 10.99 * 12, overview.could_save_yearly.amount.to_f, 0.01
  end

  private
    def subscription(name, amount)
      @family.recurring_transactions.create!(
        account: @account, name: name, amount: amount, currency: "USD", expected_day_of_month: (Date.current - 3).day,
        status: "active", manual: true, bill_type: "subscription", dedup_scope: amount.to_s,
        last_occurrence_date: Date.current - 3, next_expected_date: (Date.current - 3).next_month
      )
    end
end
