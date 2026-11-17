# Fulas Bank: «Plan de acciones» of the Forecast: bonuses paid partly in the
# company's shares (see StockPlan), and the years of each one.
class ForecastStockPlansController < ApplicationController
  before_action :set_plan, only: %i[edit update destroy]

  def index
    @plans = Current.family.stock_plans.includes(:grants, :security, :investment_account, :cash_account).alphabetically
  end

  def new
    account = investment_accounts.first
    @plan = Current.family.stock_plans.new(name: t(".default_name"), investment_account: account, currency: account&.currency)
  end

  def create
    @plan = Current.family.stock_plans.new(plan_params)

    if @plan.save
      redirect_to forecast_stock_plans_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @plan.update(plan_params)
      redirect_to forecast_stock_plans_path, notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @plan.destroy!
    redirect_to forecast_stock_plans_path, notice: t(".success")
  end

  private
    def set_plan
      @plan = Current.family.stock_plans.find(params[:id])
    end

    def investment_accounts
      @investment_accounts ||= accessible_accounts.visible.where(accountable_type: "Investment").alphabetically.to_a
    end
    helper_method :investment_accounts

    def cash_accounts
      @cash_accounts ||= accessible_accounts.visible.where(accountable_type: "Depository").alphabetically.to_a
    end
    helper_method :cash_accounts

    # The securities held in those accounts.
    def plan_securities
      @plan_securities ||= Security.where(id: Holding.where(account_id: investment_accounts.map(&:id)).select(:security_id))
                                   .order(:ticker).to_a
    end
    helper_method :plan_securities

    # The accounts and the security are not mass-assigned: each must be one
    # of the lists the form offers, and anything else is dropped.
    def plan_params
      permitted = params.require(:stock_plan).permit(:name, :base_bonus, :stock_percent, :tax_percent, :gift_every, :lock_years)
      raw = params[:stock_plan]

      if raw.key?(:investment_account_id)
        account = investment_accounts.find { |candidate| candidate.id == raw[:investment_account_id].to_s }
        permitted[:investment_account_id] = account&.id
        permitted[:currency] = account&.currency
      end
      if raw.key?(:security_id)
        permitted[:security_id] = plan_securities.find { |candidate| candidate.id == raw[:security_id].to_s }&.id
      end
      if raw.key?(:cash_account_id)
        permitted[:cash_account_id] = cash_accounts.find { |candidate| candidate.id == raw[:cash_account_id].to_s }&.id
      end
      permitted
    end
end
