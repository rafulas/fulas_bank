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

  test "linking a movement to a refuel already typed opens that refuel instead of a new one" do
    typed = @vehicle.logs.create!(kind: "fuel", date: 2.days.ago.to_date, odometer: 115_353, quantity: 35.44, amount: 70)
    charge = create_transaction(name: "REPSOL", amount: 75.29, date: 2.days.ago.to_date)

    get new_vehicle_log_url(@account, kind: "fuel", entry_id: charge.id)
    assert_redirected_to edit_vehicle_log_url(@account, typed, entry_id: charge.id)

    follow_redirect!
    assert_response :success
    assert_select "option[value='#{charge.id}'][selected]"

    assert_no_difference -> { @vehicle.logs.count } do
      patch vehicle_log_url(@account, typed), params: { vehicle_log: { entry_id: charge.id } }
    end
    assert_equal charge, typed.reload.entry
    assert_equal BigDecimal("70"), typed.amount
  end

  test "suggests bank charges for the date and amount being entered" do
    charge = create_transaction(name: "REPSOL CARD", amount: 61.2, date: 12.days.ago.to_date, account: accounts(:credit_card))

    get bank_charges_vehicle_logs_url(@account, date: 12.days.ago.to_date.iso8601, amount: "61.20")

    assert_response :success
    assert_select "option[value='#{charge.id}']", text: /REPSOL CARD/
    assert_select "option[value='']"
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

  test "attaches an invoice to a workshop service" do
    post vehicle_logs_url(@account), params: {
      vehicle_log: {
        kind: "service", date: Date.current, amount: 250,
        attachments: [ fixture_file_upload("profile_image.png", "image/png") ]
      }
    }

    log = @vehicle.logs.last
    assert_redirected_to account_url(@account, tab: "workshop")
    assert_equal [ "profile_image.png" ], log.attachments.map { |attachment| attachment.filename.to_s }
  end

  test "adds files to a log that already has some, and removes one" do
    log = @vehicle.logs.create!(kind: "service", date: Date.current, amount: 100)
    log.attachments.attach(fixture_file_upload("profile_image.png", "image/png"))

    patch vehicle_log_url(@account, log), params: {
      vehicle_log: { amount: 100, attachments: [ fixture_file_upload("profile_image.png", "image/png") ] }
    }
    assert_equal 2, log.reload.attachments.count

    get vehicle_log_attachment_url(@account, log, log.attachments.first)
    assert_response :redirect

    assert_difference -> { log.reload.attachments.count } => -1 do
      delete vehicle_log_attachment_url(@account, log, log.attachments.first)
    end
    assert_redirected_to edit_vehicle_log_url(@account, log)
  end

  test "rejects a file that is not an image or a PDF" do
    assert_no_difference -> { @vehicle.logs.count } do
      post vehicle_logs_url(@account), params: {
        vehicle_log: {
          kind: "service", date: Date.current, amount: 250,
          attachments: [ fixture_file_upload("test.txt", "text/plain") ]
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "the overview shows the vehicle sheet, total cost and consumption chart" do
    @vehicle.logs.create!(kind: "fuel", date: 20.days.ago.to_date, odometer: 10_000, quantity: 40, amount: 60)
    @vehicle.logs.create!(kind: "fuel", date: 10.days.ago.to_date, odometer: 10_500, quantity: 30, amount: 45)
    @vehicle.logs.create!(kind: "fuel", date: Date.current, odometer: 11_000, quantity: 35, amount: 52)

    get account_url(@account)

    assert_response :success
    assert_select "[data-controller='vehicle-consumption-chart']"
    assert_includes response.body, I18n.t("vehicles.tabs.vehicle_sheet.title")
    assert_includes response.body, I18n.t("vehicles.tabs.overview.total_cost")
  end

  test "a read-only member cannot add logs" do
    sign_in users(:family_member)

    assert_no_difference -> { Vehicle::Log.count } do
      post vehicle_logs_url(@account), params: { vehicle_log: { kind: "expense", category: "toll", date: Date.current, amount: 5 } }
    end
  end
end
