require "test_helper"

class ForecastScenariosControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
  end

  test "lists the scenarios and creates one" do
    get forecast_scenarios_url
    assert_response :success

    assert_difference -> { @family.scenarios.count } do
      post forecast_scenarios_url, params: { scenario: { name: "Cancelar préstamos" } }
    end
    assert_redirected_to forecast_scenario_url(@family.scenarios.last)
  end

  test "adds each kind of change and compares the forecast" do
    scenario = @family.scenarios.create!(name: "Febrero")
    starts_on = (Date.current >> 3).beginning_of_month

    ScenarioChange::KINDS.each do |kind|
      get new_forecast_scenario_change_url(scenario, kind: kind)
      assert_response :success
    end

    post forecast_scenario_changes_url(scenario), params: { scenario_change: {
      kind: "cancel_loan", loan_account_id: accounts(:loan).id, starts_on: starts_on, payoff_mode: "pending"
    } }
    post forecast_scenario_changes_url(scenario), params: { scenario_change: {
      kind: "add_movement", name: "Coche nuevo", nature: "outflow", frequency: "monthly", amount: 250, starts_on: starts_on
    } }
    post forecast_scenario_changes_url(scenario), params: { scenario_change: {
      kind: "adjust_variable", nature: "inflow", amount: 100, starts_on: starts_on
    } }
    assert_equal 3, scenario.scenario_changes.count

    get forecast_scenario_url(scenario)
    assert_response :success
    assert_select "[data-controller='scenario-chart']"

    get forecast_scenario_url(scenario, period: "1y")
    assert_response :success
  end

  test "ignores a loan from another family" do
    scenario = @family.scenarios.create!(name: "Ajeno")
    other_loan = Account.create!(family: families(:empty), owner: users(:empty), name: "Ajeno", balance: 1_000, currency: "USD",
                                 accountable: Loan.new, status: "active")

    assert_no_difference -> { scenario.scenario_changes.count } do
      post forecast_scenario_changes_url(scenario), params: { scenario_change: {
        kind: "cancel_loan", loan_account_id: other_loan.id, starts_on: Date.current >> 1
      } }
    end
    assert_response :unprocessable_entity
  end

  test "edits and removes a change, and deletes the scenario" do
    scenario = @family.scenarios.create!(name: "Borrar")
    change = scenario.scenario_changes.create!(kind: "add_movement", name: "Viaje", amount: 1_200, starts_on: Date.current >> 2)

    get edit_forecast_scenario_change_url(scenario, change)
    assert_response :success
    patch forecast_scenario_change_url(scenario, change), params: { scenario_change: { amount: 1_500 } }
    assert_equal 1_500, change.reload.amount

    delete forecast_scenario_change_url(scenario, change)
    assert_not ScenarioChange.exists?(change.id)

    delete forecast_scenario_url(scenario)
    assert_not Scenario.exists?(scenario.id)
  end

  test "another family's scenario is not found" do
    other = families(:empty).scenarios.create!(name: "Ajeno")

    get forecast_scenario_url(other)
    assert_response :not_found
  end
end
