require "test_helper"

class AccountBalancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "shows every account's balance in one form" do
    get account_balances_url

    assert_response :success
    assert_select "input[name=?]", "balances[#{accounts(:depository).id}]"
    assert_select "input[name=?]", "balances[#{accounts(:loan).id}]"
    assert_select "input[name=?]", "balances[#{accounts(:connected).id}]", count: 0
  end

  test "saves the balances changed" do
    depository = accounts(:depository)

    patch account_balances_url, params: { balances: { depository.id => "6000.00", accounts(:other_asset).id => "550.00" } }

    assert_redirected_to account_balances_url
    assert_equal 6000, depository.reload.balance
    assert_equal I18n.t("account_balances.update.success", count: 1), flash[:notice]
  end

  test "says so when nothing changed" do
    patch account_balances_url, params: { balances: { accounts(:depository).id => "5000.00" } }

    assert_redirected_to account_balances_url
    assert_equal I18n.t("account_balances.update.nothing_changed"), flash[:notice]
  end

  test "lists the balances it could not save" do
    patch account_balances_url, params: { balances: { accounts(:depository).id => "abc" } }

    assert_redirected_to account_balances_url
    follow_redirect!
    assert_select "li", text: /Checking Account/
  end

  test "the accounts side panel links to it" do
    get root_url

    assert_select "#account-sidebar-tabs a[href=?]", account_balances_path
  end

  test "the accounts page links to it" do
    get accounts_url

    assert_select "a[href=?]", account_balances_path
  end
end
