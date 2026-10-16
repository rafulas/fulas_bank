require "test_helper"

class DuplicateChargesTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @account = accounts(:depository)
    @today = Date.current
  end

  test "same amount and description on the same day or the next is a possible duplicate" do
    first = create_transaction(account: @account, name: "Gasolinera Repsol", amount: 54.30, date: @today - 3)
    second = create_transaction(account: @account, name: "GASOLINERA  repsol", amount: 54.30, date: @today - 2)
    create_transaction(account: @account, name: "Gasolinera Repsol", amount: 54.30, date: @today - 20)
    create_transaction(account: @account, name: "Gasolinera Repsol", amount: 41.00, date: @today - 2)

    pairs = finder.pairs.select { |pair| pair.name.downcase.include?("repsol") }

    assert_equal 1, pairs.size
    assert_equal [ first.id, second.id ].sort, [ pairs.first.first.id, pairs.first.second.id ].sort
  end

  test "a pair marked as fine is not shown again" do
    create_transaction(account: @account, name: "Cafetería Sol", amount: 3.20, date: @today)
    create_transaction(account: @account, name: "Cafetería Sol", amount: 3.20, date: @today)

    pair = finder.pairs.find { |candidate| candidate.name == "Cafetería Sol" }
    DuplicateCharges.dismiss!(@user, pair.key)

    assert_nil finder.pairs.find { |candidate| candidate.name == "Cafetería Sol" }
  end

  test "income and transfers are left out" do
    create_transaction(account: @account, name: "Bizum de Ana", amount: -20, date: @today)
    create_transaction(account: @account, name: "Bizum de Ana", amount: -20, date: @today)
    create_transfer(from_account: @account, to_account: accounts(:investment), amount: 300, date: @today)
    create_transfer(from_account: @account, to_account: accounts(:investment), amount: 300, date: @today)

    names = finder.pairs.map(&:name)

    assert_not_includes names, "Bizum de Ana"
    assert names.none? { |name| name.start_with?("Transfer to") }
  end

  private
    def finder
      DuplicateCharges.new(@family, user: @user.reload, today: @today)
    end
end
