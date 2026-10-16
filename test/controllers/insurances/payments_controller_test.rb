require "test_helper"

class Insurances::PaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @checking = accounts(:depository)
    @due = Date.current - 10
    @insurance = @family.insurances.create!(
      name: "Seguro Cupra", kind: "car", payment_frequency: "custom",
      installments: [ { "date" => @due.iso8601, "amount" => "150" } ]
    )
    @charge = @checking.entries.create!(name: "MAPFRE", date: @due, amount: 150, currency: "USD", entryable: Transaction.new)
  end

  test "links an instalment to its charge, shows it on both sides and undoes it" do
    get edit_insurance_path(@insurance)
    assert_select "form[action=?]", link_insurance_payment_path(@insurance, @due.iso8601, entry_id: @charge.id)

    post link_insurance_payment_path(@insurance, @due.iso8601, entry_id: @charge.id)
    payment = @insurance.insurance_payments.find_by!(due_on: @due)
    assert payment.paid?
    assert_equal @charge, payment.entry

    get transaction_path(@charge)
    assert_select "a[href=?]", edit_insurance_path(@insurance)

    delete clear_insurance_payment_path(@insurance, @due.iso8601)
    assert_not payment.reload.paid?
  end

  test "marks an instalment paid without a charge" do
    post mark_paid_insurance_payment_path(@insurance, @due.iso8601)

    assert @insurance.insurance_payments.find_by!(due_on: @due).paid_manually?
  end

  test "only the policy's instalment days exist" do
    post mark_paid_insurance_payment_path(@insurance, (@due + 1).iso8601)

    assert_response :not_found
  end
end
