require "test_helper"

class Properties::ExpensesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:property)
    @property = @account.property
  end

  test "new expense form, prefilled from a bank movement" do
    charge = create_transaction(name: "REFORMAS PEREZ", amount: 1_250, date: 3.days.ago.to_date)

    get new_property_expense_url(@account, kind: "renovation", entry_id: charge.id)

    assert_response :success
    assert_select "option[value='#{charge.id}'][selected]", text: /REFORMAS PEREZ/
    assert_select "option[value='renovation'][selected]"
  end

  test "records an expense linked to a bank charge" do
    charge = create_transaction(name: "MAPFRE HOGAR", amount: 320.4)

    assert_difference -> { @property.expenses.count } => 1 do
      post property_expenses_url(@account), params: {
        property_expense: { kind: "insurance", date: Date.current, amount: "", entry_id: charge.id, notes: "Póliza anual" }
      }
    end

    expense = @property.expenses.last
    assert_equal charge, expense.entry
    assert_equal BigDecimal("320.4"), expense.amount
    assert_redirected_to account_url(@account, tab: "expenses")
  end

  test "saving a suggested expense confirms it" do
    charge = create_transaction(name: "COMUNIDAD", amount: 90)
    expense = @property.expenses.create!(kind: "community", date: Date.current, entry: charge, suggestion: "new")

    patch property_expense_url(@account, expense), params: { property_expense: { kind: "community", notes: "Cuota" } }

    assert_nil expense.reload.suggestion
    assert_equal "Cuota", expense.notes
  end

  test "the property page shows the expenses tab" do
    @property.expenses.create!(kind: "renovation", date: Date.current, amount: 500, notes: "Baño")

    get account_url(@account, tab: "expenses")

    assert_response :success
  end
end
