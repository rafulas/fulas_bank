require "test_helper"

class AccountValuationImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @account = accounts(:other_asset)
    @account.entries.destroy_all
  end

  test "upload form" do
    get new_account_valuation_import_url(@account)

    assert_response :success
    assert_select "input[type=file][name=file]"
  end

  test "shows what would be imported before saving anything" do
    file = Rack::Test::UploadedFile.new(file_fixture("imports/valores_poliza.xlsx"), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    assert_no_difference -> { @account.entries.count } do
      post account_valuation_import_url(@account), params: { file: file }
    end

    assert_response :success
    assert_select "input[name=content]"
    assert_select "input[name=confirm]"
  end

  test "imports the values once confirmed" do
    content = Base64.strict_encode64("Fecha;Valor\n31/01/2024;18000\n29/02/2024;18250,50\n")

    assert_difference -> { @account.entries.valuations.count }, 2 do
      post account_valuation_import_url(@account), params: { content: content, confirm: "1" }
    end

    assert_redirected_to account_url(@account)
    assert_equal 18250.5, @account.entries.find_by(date: Date.new(2024, 2, 29)).amount.to_f
  end

  test "explains when the file has no date and value columns" do
    post account_valuation_import_url(@account), params: { file: fixture_file_upload("test.txt", "text/plain") }

    assert_response :unprocessable_entity
  end

  test "not offered for accounts whose balance comes from their transactions" do
    get new_account_valuation_import_url(accounts(:depository))

    assert_redirected_to account_url(accounts(:depository))
  end
end
