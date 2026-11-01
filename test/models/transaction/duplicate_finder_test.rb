require "test_helper"

class Transaction::DuplicateFinderTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @account = accounts(:depository)
    @food = categories(:food_and_drink)
    @day = Date.new(2025, 3, 10)
  end

  test "same amount and category, at most a day apart, in any of the accounts" do
    first = create_transaction(account: @account, name: "Súper", amount: 42.5, date: @day, category: @food)
    next_day = create_transaction(account: accounts(:credit_card), name: "SUPER", amount: 42.5, date: @day + 1, category: @food)
    create_transaction(account: @account, name: "Otra categoría", amount: 42.5, date: @day, category: categories(:one))
    create_transaction(account: @account, name: "Dos días después", amount: 42.5, date: @day + 3, category: @food)
    create_transaction(account: @account, name: "Otro importe", amount: 42.6, date: @day, category: @food)

    assert_equal [ first.id, next_day.id ].map(&:to_s).sort, finder.entry_ids.sort
  end

  test "a pair said to be fine is not shown again, also on Inicio's list" do
    first = create_transaction(account: @account, name: "Café", amount: 1.5, date: @day, category: @food)
    second = create_transaction(account: @account, name: "Café", amount: 1.5, date: @day, category: @food)

    assert_equal 1, finder.dismiss!([ first.id, second.id ])
    assert_empty finder.entry_ids
    assert_includes @user.reload.preferences[DuplicateCharges::PREFERENCE_KEY], [ first.id, second.id ].map(&:to_s).sort.join(":")
  end

  private
    def finder
      Transaction::DuplicateFinder.new(@family, account_ids: @family.accounts.pluck(:id), user: @user.reload)
    end
end
