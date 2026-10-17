require "test_helper"

class SmartImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @account = accounts(:depository)
  end

  test "a bank statement goes to the account with its IBAN" do
    @account.update!(statement_reference: "0182-1234")

    post smart_imports_path, params: { file: fixture_file_upload("imports/bbva.xlsx", Import::XLSX_MIME_TYPES.first) }

    import = @family.imports.order(:created_at).last
    assert_redirected_to import_configuration_path(import)
    assert_equal @account, import.account
    assert_equal "0182-1234", import.statement_reference
  end

  test "asks for the account when it cannot tell, and then goes on" do
    @family.accounts.create!(name: "Otra cuenta", owner: users(:family_admin), balance: 0, currency: "USD", accountable: Depository.new)

    post smart_imports_path, params: { file: fixture_file_upload("imports/bbva.xlsx", Import::XLSX_MIME_TYPES.first) }

    import = @family.imports.order(:created_at).last
    assert_redirected_to edit_smart_import_path(import)

    get edit_smart_import_path(import)
    assert_response :success

    patch smart_import_path(import, account_id: @account.id)
    assert_redirected_to import_configuration_path(import)
    assert_equal @account, import.reload.account
  end

  test "a Bilance export imports every account it names" do
    post smart_imports_path, params: { file: fixture_file_upload("imports/bilance.csv", "text/csv") }

    import = @family.imports.order(:created_at).last
    assert_redirected_to import_configuration_path(import)
    assert_nil import.account
  end

  test "a RoadTrip export goes to the vehicle, straight to its preview" do
    post smart_imports_path, params: { file: fixture_file_upload("roadtrip_export.csv", "text/csv") }

    assert_response :success
    assert_select "form[action=?]", vehicle_roadtrip_import_path(accounts(:vehicle))
  end

  test "rejects files it does not know" do
    post smart_imports_path, params: { file: fixture_file_upload("profile_image.png", "image/png") }

    assert_redirected_to new_import_path
  end
end
