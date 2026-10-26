require "test_helper"

class Account::BalanceBulkUpdateTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @admin = users(:family_admin)
  end

  test "lists the manual accounts the user can change, by type" do
    accounts = editor.accounts

    assert_includes accounts, accounts(:depository)
    assert_includes accounts, accounts(:loan)
    assert_not_includes accounts, accounts(:connected)
    assert_equal accounts.map(&:accountable_type).uniq,
                 accounts.map(&:accountable_type).uniq.sort_by { |type| Accountable::TYPES.index(type) }
  end

  test "leaves out accounts only shared to read" do
    accounts = editor(user: users(:family_member)).accounts

    assert_includes accounts, accounts(:depository)
    assert_not_includes accounts, accounts(:credit_card)
  end

  test "changes only the balances typed differently" do
    depository = accounts(:depository)
    other_asset = accounts(:other_asset)

    result = editor.apply(depository.id => "6000.00", other_asset.id => "550.00", accounts(:property).id => "")

    assert_equal [ depository ], result.updated
    assert_empty result.failures
    assert_equal 6000, depository.reload.balance
    assert_equal 550, other_asset.reload.balance
  end

  test "reads a comma decimal" do
    depository = accounts(:depository)

    editor.apply(depository.id => "6.000,50")

    assert_equal BigDecimal("6000.5"), depository.reload.balance
  end

  test "a loan's balance is what is owed, with or without a minus" do
    loan = accounts(:loan)
    Account.any_instance.expects(:set_current_balance).with(BigDecimal("1000")).returns(
      Account::CurrentBalanceManager::Result.new(success?: true, changes_made?: true)
    )

    result = editor.apply(loan.id => "-1000")

    assert_equal [ loan ], result.updated
  end

  test "reports an amount it can't read and keeps going" do
    depository = accounts(:depository)
    other_asset = accounts(:other_asset)

    result = editor.apply(depository.id => "abc", other_asset.id => "600")

    assert_equal [ depository ], result.failures.map(&:account)
    assert_equal [ other_asset ], result.updated
    assert_equal 5000, depository.reload.balance
  end

  test "ignores accounts it doesn't list" do
    linked = accounts(:connected)

    result = editor.apply(linked.id => "1")

    assert_empty result.updated
    assert_equal 5000, linked.reload.balance
  end

  private
    def editor(user: @admin)
      Account::BalanceBulkUpdate.new(family: @family, user: user)
    end
end
