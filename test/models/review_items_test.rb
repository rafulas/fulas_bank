require "test_helper"

class ReviewItemsTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @series = recurring_transactions(:netflix_subscription)
  end

  test "gathers price rises and possible double charges" do
    @series.recurring_price_changes.create!(effective_on: 3.days.ago.to_date, previous_amount: 12.99, new_amount: 15.99, currency: "USD", source: "detected")
    create_transaction(account: accounts(:depository), name: "Panadería Lola", amount: 4.10, date: Date.current)
    create_transaction(account: accounts(:depository), name: "Panadería Lola", amount: 4.10, date: Date.current)

    kinds = review.items.map(&:kind)

    assert_includes kinds, :price_increase
    assert_includes kinds, :duplicate
  end

  test "an item marked as seen leaves the list" do
    change = @series.recurring_price_changes.create!(effective_on: 3.days.ago.to_date, previous_amount: 12.99, new_amount: 15.99, currency: "USD", source: "detected")

    ReviewItems.mark_seen!(@user, "price:#{change.id}")

    assert_not review.items.any? { |item| item.key == "price:#{change.id}" }
  end

  test "a price drop is not worth a warning" do
    @series.recurring_price_changes.create!(effective_on: 3.days.ago.to_date, previous_amount: 19.99, new_amount: 15.99, currency: "USD", source: "detected")

    assert_not_includes review.items.map(&:kind), :price_increase
  end

  test "an overdue insurance instalment is listed and can be marked seen" do
    travel_to Date.new(2026, 11, 17)
    insurance = @family.insurances.create!(
      name: "Seguro moto", kind: "motorcycle", payment_frequency: "custom", payment_account: accounts(:depository),
      installments: [ { "date" => "2026-11-10", "amount" => "120" } ]
    )

    item = review.items.find { |entry| entry.kind == :overdue && entry.title == "Seguro moto" }
    assert item, "the overdue instalment is listed"
    assert_match ReviewItemsController::KEY_FORMAT, item.key
    assert_includes item.key, insurance.id

    ReviewItems.mark_seen!(@user, item.key)

    assert_not review.items.any? { |entry| entry.key == item.key }
  end

  private
    def review
      ReviewItems.new(@family, user: @user.reload)
    end
end
