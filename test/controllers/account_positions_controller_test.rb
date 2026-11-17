require "test_helper"

class AccountPositionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @first = Account.create!(family: @family, owner: @user, name: "AAA orden", balance: 10, currency: "USD", accountable: Depository.new, status: "active")
    @last = Account.create!(family: @family, owner: @user, name: "ZZZ orden", balance: 10, currency: "USD", accountable: Depository.new, status: "active")
  end

  test "moves an account up within its group and uses the order set by hand" do
    get edit_account_positions_url
    assert_response :success
    before = depository_ids

    patch account_positions_url(account_id: @last.id, direction: "up"), as: :turbo_stream
    assert_response :success

    @user.reload
    assert_equal "manual", @user.default_account_order
    after = depository_ids
    assert_equal before.index(@last.id) - 1, after.index(@last.id)
    assert_equal before.size, after.size
  end

  test "goes back to ordering by name" do
    @user.save_account_positions!([ @last.id ])

    delete account_positions_url

    assert_equal "name_asc", @user.reload.default_account_order
  end

  test "an account from another family is not found" do
    other = Account.create!(family: families(:empty), owner: users(:empty), name: "Ajena", balance: 1, currency: "USD", accountable: Depository.new, status: "active")

    patch account_positions_url(account_id: other.id, direction: "up")
    assert_response :not_found
  end

  private
    def depository_ids
      BalanceSheet.new(@family, user: @user.reload).assets.account_groups.find { |group| group.key == "depository" }.accounts.map(&:id)
    end
end
