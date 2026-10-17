require "test_helper"

class Transactions::RecurringAssignmentsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in users(:family_admin)
    @account = accounts(:depository)
  end

  test "shows the list with the option to create a new one and the frequencies" do
    get new_transactions_recurring_assignment_url

    assert_response :success
    assert_select "button[data-recurring-picker-id-param='new']"
    assert_select "input[type=radio][name='recurring_assignment[frequency]']", count: RecurringAssignment::FREQUENCIES.size
  end

  test "adds the selected movements to a new series in one go" do
    entries = 2.times.map { |index| create_transaction(account: @account, name: "NOMINA", amount: -1_500, date: (Date.current - 10).prev_month(index)) }

    assert_difference -> { RecurringTransaction.count }, 1 do
      post transactions_recurring_assignment_url, params: { recurring_assignment: {
        series_id: "new", name: "Nómina Rafa BBVA", frequency: "monthly", entry_ids: entries.map(&:id)
      } }
    end

    assert_redirected_to transactions_url
    assert_equal "Nómina Rafa BBVA", RecurringTransaction.order(:created_at).last.name
  end

  test "the movement's detail offers it" do
    entry = create_transaction(account: @account, name: "NOMINA", amount: -1_500, date: Date.current - 3)

    get transaction_url(entry)

    assert_select "a[href=?]", new_transactions_recurring_assignment_path(entry_ids: [ entry.id ])
  end
end
