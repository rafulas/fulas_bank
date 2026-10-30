require "test_helper"

class Import::DuplicatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @import = imports(:transaction)
    account = accounts(:depository)
    account.entries.create!(date: Date.new(2024, 1, 17), amount: 30, currency: "USD", name: "Cena Urogallo", entryable: Transaction.new)
    @import.update!(
      account: account,
      raw_file_str: "date,name,amount\n01/18/2024,RESTAURANTE UROGALLO POZUELO,30\n",
      date_col_label: "date", amount_col_label: "amount", name_col_label: "name",
      date_format: "%m/%d/%Y", amount_type_strategy: "signed_amount", signage_convention: "inflows_negative"
    )
    @import.generate_rows_from_csv
    @row = @import.rows.first
  end

  test "the review offers the movement entered by hand and saves the choice" do
    TransactionImport.any_instance.stubs(:publishable?).returns(true)
    get import_url(@import)
    assert_response :success
    assert_select "#possible-duplicates input[name='choice'][value='file']"

    patch import_duplicate_url(@import), params: { row_id: @row.id, choice: "file" }
    assert_redirected_to import_url(@import, anchor: "possible-duplicates")
    assert_equal "file", @row.reload.duplicate_choice

    patch import_duplicate_url(@import), params: { row_id: @row.id, choice: "nonsense" }
    assert_equal "file", @row.reload.duplicate_choice
  end
end
