require "test_helper"

class Transactions::PanelAccountsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
  end

  test "the movements list starts with the panel and each month's summary" do
    create_transaction(account: accounts(:depository), name: "Mercado", amount: 40, date: Date.current)

    get transactions_url

    assert_response :success
    assert_select "#transactions-panel"
    assert_select "#month-summary-#{Date.current.strftime('%Y-%m')}"
  end

  test "the next block of movements comes in its own frame" do
    12.times { |index| create_transaction(account: accounts(:depository), name: "Bloque #{index}", amount: 5, date: Date.current - index) }

    get transactions_url(page: 2, per_page: 10, after_month: Date.current.beginning_of_month.iso8601),
        headers: { "Turbo-Frame" => "transactions_page_2" }

    assert_response :success
    assert_select "turbo-frame#transactions_page_2"
    assert_select "#transactions-panel", count: 0
  end

  test "chooses the panel accounts, keeping only the user's own" do
    get edit_transactions_panel_accounts_url
    assert_response :success

    other_family_account = Account.where.not(family_id: @user.family_id).first
    patch transactions_panel_accounts_url, params: { account_ids: [ accounts(:depository).id, other_family_account&.id ].compact }

    assert_redirected_to transactions_url
    assert_equal [ accounts(:depository).id ], @user.reload.transactions_panel_account_ids
  end

  test "opening the list from the menu starts without the filters used before" do
    get transactions_url(q: { types: [ "income" ], start_date: (Date.current - 30).iso8601 })
    assert_response :success

    get transactions_url

    assert_response :success
    assert_select "#transactions-panel"
  end
end
