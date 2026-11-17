# Fulas Bank: the changes of a scenario (ScenarioChange), added, edited and
# removed from the scenario's page.
class ForecastScenarioChangesController < ApplicationController
  include ForecastBuilding

  before_action :set_scenario
  before_action :set_change, only: %i[edit update destroy]
  helper_method :recurring_options, :loan_options, :account_options

  def new
    kind = ScenarioChange::KINDS.include?(params[:kind]) ? params[:kind] : ScenarioChange::KINDS.first
    @change = @scenario.scenario_changes.new(kind: kind, starts_on: Date.current.next_month.beginning_of_month)
  end

  def create
    @change = @scenario.scenario_changes.new(change_params)

    if @change.save
      redirect_to forecast_scenario_path(@scenario), notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @change.update(change_params)
      redirect_to forecast_scenario_path(@scenario), notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @change.destroy!
    redirect_to forecast_scenario_path(@scenario), notice: t(".success")
  end

  private
    def set_scenario
      @scenario = Current.family.scenarios.find(params[:scenario_id])
    end

    def set_change
      @change = @scenario.scenario_changes.find(params[:id])
    end

    # The records are not mass-assigned blindly: each must be one the user
    # can see, or it is dropped (and the change fails validation).
    def change_params
      permitted = params.require(:scenario_change).permit(:kind, :starts_on, :ends_on, :name, :amount, :nature, :frequency, :payoff_mode)
      raw = params[:scenario_change]

      chosen = {
        recurring_transaction_id: recurring_options,
        loan_account_id: loan_options,
        account_id: account_options
      }.filter_map do |key, options|
        next unless raw.key?(key)

        [ key, options.find { |record| record.id == raw[key].to_s }&.id ]
      end.to_h

      permitted.merge(chosen)
    end

    def recurring_options
      @recurring_options ||= Current.family.recurring_transactions.active.to_a.sort_by { |series| series.display_name.to_s.downcase }
    end

    def loan_options
      @loan_options ||= accessible_accounts.visible.where(accountable_type: "Loan").includes(:accountable).alphabetically
                                           .reject { |account| account.accountable.paid_off? }
    end

    def account_options
      forecast_accounts
    end
end
