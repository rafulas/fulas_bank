# Fulas Bank: «Escenarios» of the Forecast: «what if» versions of it (see
# Scenario), each compared month by month with the forecast as it is.
class ForecastScenariosController < ApplicationController
  include ForecastBuilding

  # Horizons for the comparison; five years, like the Forecast, by default.
  PERIODS = { "1y" => 12, "2y" => 24, "5y" => 60 }.freeze
  DEFAULT_PERIOD = "5y"

  before_action :set_scenario, only: %i[show edit update destroy]

  def index
    @scenarios = Current.family.scenarios.includes(:scenario_changes).alphabetically
  end

  def show
    sync_loan_installments
    @period = PERIODS.key?(params[:period]) ? params[:period] : DEFAULT_PERIOD
    @accounts = forecast_accounts
    through = Date.current >> PERIODS.fetch(@period)
    main_account = saved_main_account(@accounts)

    base = build_forecast_for(accounts: @accounts, through: through, main_account: main_account)
    with_changes = build_forecast_for(accounts: @accounts, through: through, main_account: main_account, scenario: @scenario)
    @comparison = Scenario::Comparison.new(base: base, scenario_forecast: with_changes)
  end

  def new
    @scenario = Current.family.scenarios.new
  end

  def create
    @scenario = Current.family.scenarios.new(scenario_params)

    if @scenario.save
      redirect_to forecast_scenario_path(@scenario), notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @scenario.update(scenario_params)
      redirect_to forecast_scenario_path(@scenario), notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @scenario.destroy!
    redirect_to forecast_scenarios_path, notice: t(".success")
  end

  private
    def set_scenario
      @scenario = Current.family.scenarios
                         .includes(scenario_changes: [ :recurring_transaction, :account, { loan_account: :accountable } ])
                         .find(params[:id])
    end

    def scenario_params
      params.require(:scenario).permit(:name, :notes)
    end
end
