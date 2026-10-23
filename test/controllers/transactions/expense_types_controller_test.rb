require "test_helper"

class Transactions::ExpenseTypesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @entry = create_transaction(account: accounts(:depository), name: "Academia", amount: 80, date: Date.current - 3)
  end

  test "the detail shows the type and the form" do
    get transaction_url(@entry)

    assert_response :success
    assert_select "form[action='#{transaction_expense_type_path(@entry)}']"
    assert_select "select[name='expense_type[expense_type]'] option[selected][value='variable']"
  end

  test "marks a movement recurring for a number of payments" do
    assert_difference -> { @user.family.recurring_transactions.count } => 1 do
      patch transaction_expense_type_url(@entry), params: { expense_type: { expense_type: "recurring", ends_by: "periods", periods: "10", end_on: "" } }
    end

    assert_redirected_to transaction_url(@entry)
    transaction = Transaction.find(@entry.entryable_id)
    assert_equal "fixed", transaction.expense_type
    assert transaction.recurring_series.ends_on_date?
  end

  test "says why it cannot save" do
    patch transaction_expense_type_url(@entry), params: { expense_type: { expense_type: "recurring", ends_by: "date", end_on: "" } }

    assert_redirected_to transaction_url(@entry)
    assert_equal I18n.t("transactions.expense_types.update.errors.end_required"), flash[:alert]
  end
end
