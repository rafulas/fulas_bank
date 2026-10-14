require "test_helper"

class Import::BalanceChecksControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:depository)
    csv = "Fecha;Concepto;Importe;Disponible\n#{Date.current.strftime('%d/%m/%Y')};MERCADONA;-50,00;950,00\n"
    @import = @user.family.imports.create!(type: "TransactionImport", account: @account, raw_file_str: csv, col_sep: ";", status: :complete)
    Import::BankPreset.apply(@import)
    @import.reload.generate_rows_from_csv
    create_transaction(account: @account, name: "MERCADONA", amount: 50, import: @import)
    @account.balances.create!(date: Date.current, balance: 1000, currency: "USD", start_cash_balance: 1000)
  end

  test "the finished import says whether the balances match" do
    get import_url(@import)

    assert_response :success
    assert_select "turbo-frame#import_balance_check"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@account, :balance_check)}"
    assert_select "form[action='#{adjust_import_balance_check_path(@import, account_id: @account.id)}']"
  end

  test "checks a typed balance" do
    patch import_balance_check_url(@import, account_id: @account.id), params: { balance_check: { amount: "1000" } }

    assert_redirected_to import_balance_check_url(@import)
    assert_equal({ "amount" => "1000.0", "date" => Date.current.iso8601 },
                 @import.reload.summary.dig(Import::BalanceCheck::SUMMARY_KEY, @account.id))

    get import_balance_check_url(@import), headers: { "Turbo-Frame" => "import_balance_check" }
    assert_response :success
    assert_select "turbo-frame#import_balance_check"
  end

  test "rejects an amount that is not a number" do
    patch import_balance_check_url(@import, account_id: @account.id), params: { balance_check: { amount: "mucho" } }

    assert_redirected_to import_balance_check_url(@import)
    assert_nil @import.reload.summary[Import::BalanceCheck::SUMMARY_KEY]
  end

  test "adjusts the account to the statement's balance" do
    assert_difference -> { @account.entries.where(entryable_type: "Valuation").count } => 1 do
      post adjust_import_balance_check_url(@import, account_id: @account.id)
    end

    assert_redirected_to import_balance_check_url(@import)
  end

  test "only for the family's own imports and the accounts they touched" do
    other_account = accounts(:credit_card)

    patch import_balance_check_url(@import, account_id: other_account.id), params: { balance_check: { amount: "10" } }
    assert_response :not_found

    get import_balance_check_url(imports(:transaction))
    assert_response :not_found
  end
end
