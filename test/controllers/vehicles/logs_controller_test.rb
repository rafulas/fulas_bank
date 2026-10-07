require "test_helper"

class Vehicles::LogsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:vehicle)
    @vehicle = @account.vehicle
  end

  test "new refuel form" do
    get new_vehicle_log_url(@account, kind: "fuel")

    assert_response :success
  end

  test "records a refuel linked to a bank charge" do
    charge = create_transaction(name: "REPSOL", amount: 54.37)

    assert_difference -> { @vehicle.logs.count } => 1 do
      post vehicle_logs_url(@account), params: {
        vehicle_log: {
          kind: "fuel", date: Date.current, odometer: 62_400, quantity: 35.5, unit_price: "", amount: "",
          full_tank: "1", entry_id: charge.id, notes: "Repsol"
        }
      }
    end

    log = @vehicle.logs.last
    assert_equal charge, log.entry
    assert_equal BigDecimal("54.37"), log.amount
    assert_equal @account.currency, log.currency
    assert_redirected_to account_url(@account, tab: "refuels")
  end

  test "ignores a bank charge the user cannot see" do
    other_account = families(:empty).accounts.create!(
      name: "Other family checking", balance: 0, currency: "USD", accountable: Depository.new
    )
    foreign_charge = create_transaction(account: other_account, amount: 50)

    post vehicle_logs_url(@account), params: {
      vehicle_log: { kind: "expense", category: "toll", date: Date.current, amount: 14.3, entry_id: foreign_charge.id }
    }

    assert_nil @vehicle.logs.last.entry_id
    assert_redirected_to account_url(@account, tab: "running_costs")
  end

  test "shows the form again when invalid" do
    assert_no_difference -> { @vehicle.logs.count } do
      post vehicle_logs_url(@account), params: { vehicle_log: { kind: "expense", category: "", date: Date.current, amount: 10 } }
    end

    assert_response :unprocessable_entity
  end

  test "updates and deletes a log" do
    log = @vehicle.logs.create!(kind: "service", date: Date.current, amount: 100)

    patch vehicle_log_url(@account, log), params: { vehicle_log: { amount: 139 } }
    assert_redirected_to account_url(@account, tab: "workshop")
    assert_equal BigDecimal("139"), log.reload.amount

    assert_difference -> { @vehicle.logs.count } => -1 do
      delete vehicle_log_url(@account, log)
    end
  end

  test "the vehicle page renders the logbook tabs" do
    @vehicle.logs.create!(kind: "fuel", date: 10.days.ago.to_date, odometer: 10_000, quantity: 40, amount: 60)
    @vehicle.logs.create!(kind: "fuel", date: Date.current, odometer: 10_800, quantity: 40, amount: 62)
    @vehicle.maintenance_items.create!(name: "Oil", interval_km: 15_000, last_done_odometer: 0, last_done_on: 1.year.ago.to_date)

    get account_url(@account)

    assert_response :success
    assert_select "[data-testid='account-details']"
    assert_includes response.body, "Oil"
  end

  test "a read-only member cannot add logs" do
    sign_in users(:family_member)

    assert_no_difference -> { Vehicle::Log.count } do
      post vehicle_logs_url(@account), params: { vehicle_log: { kind: "expense", category: "toll", date: Date.current, amount: 5 } }
    end
  end
end
