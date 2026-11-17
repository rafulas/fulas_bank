# Fulas Bank: a year of a «Plan de acciones» (see StockPlanGrant): the bonus,
# its part in shares and when they can be sold.
class ForecastStockPlanGrantsController < ApplicationController
  before_action :set_plan
  before_action :set_grant, only: %i[edit update destroy]

  def new
    last = @plan.grants.last
    @grant = @plan.grants.new(granted_on: last ? last.granted_on.next_year : Date.current,
                              stock_percent: @plan.stock_percent, achievement_percent: 100)
  end

  def create
    @grant = @plan.grants.new(grant_params)

    if @grant.save
      redirect_to forecast_stock_plans_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @grant.update(grant_params)
      redirect_back_or_to forecast_stock_plans_path, notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @grant.destroy!
    redirect_to forecast_stock_plans_path, notice: t(".success")
  end

  private
    def set_plan
      @plan = Current.family.stock_plans.find(params[:stock_plan_id])
    end

    def set_grant
      @grant = @plan.grants.find(params[:id])
    end

    def grant_params
      params.require(:stock_plan_grant).permit(:granted_on, :sell_on, :achievement_percent, :stock_percent, :shares, :gift_shares, :notes)
    end
end
