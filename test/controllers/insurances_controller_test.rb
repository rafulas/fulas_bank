require "test_helper"

class InsurancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @vehicle = accounts(:vehicle)
  end

  test "lists the policies, linked from the sidebar, and the assets without one" do
    insurance = @family.insurances.create!(name: "Seguro Cupra", kind: "car", insurer: "Mapfre", premium: 320, account: @vehicle)

    get insurances_url

    assert_response :success
    assert_select "a[href='#{insurances_path}']"
    assert_select "##{ActionView::RecordIdentifier.dom_id(insurance)}", text: /Seguro Cupra/
    assert_select "##{ActionView::RecordIdentifier.dom_id(accounts(:property), :uninsured)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@vehicle, :uninsured)}", count: 0
  end

  test "adds a policy tied to a vehicle, edits and deletes it" do
    get new_insurance_url
    assert_response :success

    assert_difference -> { @family.insurances.count } => 1 do
      post insurances_url, params: { insurance: {
        name: " Seguro Nine T ", kind: "motorcycle", account_id: @vehicle.id, insurer: "Mutua",
        premium: "180.50", payment_frequency: "annual", renewal_date: "2026-11-02"
      } }
    end
    assert_redirected_to insurances_url

    insurance = @family.insurances.order(:created_at).last
    assert_equal [ "Seguro Nine T", @vehicle, BigDecimal("180.5") ], [ insurance.name, insurance.account, insurance.premium ]

    get edit_insurance_url(insurance)
    assert_response :success

    patch insurance_url(insurance), params: { insurance: { active: "0", account_id: "" } }
    insurance.reload
    assert_not insurance.active?
    assert_nil insurance.account

    assert_difference -> { @family.insurances.count } => -1 do
      delete insurance_url(insurance)
    end
    assert_redirected_to insurances_url
  end

  test "opened from the vehicle's page, the form comes filled in and returns there" do
    get new_insurance_url(account_id: @vehicle.id, return_to_account: @vehicle.id)

    assert_response :success
    assert_select "select[name='insurance[account_id]'] option[selected][value='#{@vehicle.id}']"
    assert_select "select[name='insurance[kind]'] option[selected][value='car']"
    assert_select "input[name='return_to_account'][value='#{@vehicle.id}']"

    post insurances_url, params: { return_to_account: @vehicle.id, insurance: { name: "Seguro coche", kind: "car", account_id: @vehicle.id } }

    assert_redirected_to account_url(@vehicle)
  end

  test "a home policy cannot insure a car" do
    assert_no_difference -> { Insurance.count } do
      post insurances_url, params: { insurance: { name: "Hogar", kind: "home", account_id: @vehicle.id } }
    end

    assert_response :unprocessable_entity
  end

  test "only the user's vehicles and properties can be insured" do
    assert_no_difference -> { Insurance.count } do
      post insurances_url, params: { insurance: { name: "Cuenta", kind: "other", account_id: accounts(:depository).id } }
    end

    assert_response :not_found
  end

  test "another family's policy cannot be opened" do
    foreign = families(:empty).insurances.create!(name: "Ajeno", kind: "life")

    get edit_insurance_url(foreign)

    assert_response :not_found
  end

  test "the vehicle's page shows its insurance" do
    @family.insurances.create!(name: "Seguro Cupra", kind: "car", account: @vehicle, assistance_phone: "900 123 456")

    get account_url(@vehicle)

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(@vehicle, :insurances)}", text: /Seguro Cupra/
    assert_select "a[href='tel:900123456']"
  end

  test "the property's page shows its insurance" do
    @family.insurances.create!(name: "Seguro hogar", kind: "home", account: accounts(:property))

    get account_url(accounts(:property))

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(accounts(:property), :insurances)}", text: /Seguro hogar/
  end

  test "saves a policy paid in custom instalments and lists them" do
    post insurances_url, params: { insurance: {
      name: "Seguro Cupra", kind: "car", payment_frequency: "custom", start_date: "2026-09-01",
      installments: [
        { date: "2026-09-01", amount: "150" },
        { date: "2026-10-16", amount: "150" },
        { date: "2026-11-30", amount: "150" },
        { date: "", amount: "" }
      ]
    } }

    insurance = @family.insurances.find_by!(name: "Seguro Cupra")
    assert insurance.custom_payments?
    assert_equal 3, insurance.installments.size
    assert_equal BigDecimal("450"), insurance.annual_cost.amount

    get insurances_url
    assert_select "##{ActionView::RecordIdentifier.dom_id(insurance)}", text: /3 /

    get edit_insurance_url(insurance)
    assert_response :success
    assert_select "input[name='insurance[installments][][date]'][value='2026-10-16']"
  end
end
