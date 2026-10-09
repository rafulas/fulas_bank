require "test_helper"

class AssetLinksControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:vehicle)
    @vehicle = @account.vehicle
    @charge = create_transaction(name: "REPSOL", amount: 58)
  end

  test "confirms a suggestion" do
    log = @vehicle.logs.create!(kind: "fuel", date: Date.current, entry: @charge, suggestion: "new")

    patch confirm_asset_link_url(log)

    assert_nil log.reload.suggestion
    assert_redirected_to account_url(@account, tab: "overview")
  end

  test "rejects a suggestion and remembers it" do
    log = @vehicle.logs.create!(kind: "fuel", date: Date.current, entry: @charge, suggestion: "new")

    delete reject_asset_link_url(log)

    assert_not Vehicle::Log.exists?(log.id)
    assert AssetLinkRejection.exists?(entry: @charge, account: @account)
  end

  test "unlinks a confirmed link but keeps the record" do
    log = @vehicle.logs.create!(kind: "expense", category: "toll", date: Date.current, entry: @charge)

    delete unlink_asset_link_url(log)

    assert log.reload.persisted?
    assert_nil log.entry
  end

  test "searches the whole history" do
    fuel = families(:dylan_family).categories.create!(name: "Combustible", color: "#506cd8", lucide_icon: "fuel")
    old = create_transaction(name: "REPSOL", amount: 45, date: 3.years.ago.to_date, category: fuel)

    post search_asset_links_url(account_id: @account.id)

    assert_equal @vehicle, AssetLink.for_entry(old).vehicle
    assert_redirected_to account_url(@account, tab: "overview")
  end

  test "confirms all of an account's suggestions" do
    log = @vehicle.logs.create!(kind: "fuel", date: Date.current, entry: @charge, suggestion: "new")

    patch confirm_all_asset_links_url(account_id: @account.id)

    assert_nil log.reload.suggestion
  end

  test "the bank movement shows its link, and offers to link it when it has none" do
    get transaction_url(@charge), headers: { "Turbo-Frame" => "drawer" }
    assert_response :success
    assert_select "a[href*='entry_id=#{@charge.id}']"

    @vehicle.logs.create!(kind: "fuel", date: Date.current, entry: @charge)
    get transaction_url(@charge), headers: { "Turbo-Frame" => "drawer" }
    assert_response :success
    assert_select "button", text: /#{I18n.t("transactions.asset_link.unlink")}/
  end
end
