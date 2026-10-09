# One-off income or expenses the user expects (see ForecastItem), added and
# edited from the Forecast page.
class ForecastItemsController < ApplicationController
  before_action :set_item, only: %i[edit update destroy]

  def new
    @item = Current.family.forecast_items.new(nature: "outflow", date: Date.current + 1, account: forecast_accounts.first)
  end

  def create
    @item = Current.family.forecast_items.new(item_params)

    if @item.save
      redirect_to forecast_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @item.update(item_params)
      redirect_to forecast_path, notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @item.destroy!
    redirect_to forecast_path, notice: t(".success")
  end

  private
    def set_item
      @item = Current.family.forecast_items.where(account_id: forecast_accounts.map(&:id)).find(params[:id])
    end

    def forecast_accounts
      @forecast_accounts ||= accessible_accounts.visible.where(accountable_type: Forecast::ACCOUNT_TYPES).alphabetically.to_a
    end
    helper_method :forecast_accounts

    # The account is not mass-assigned: it must be one of the user's forecast
    # accounts, and anything else is dropped and fails validation.
    def item_params
      permitted = params.require(:forecast_item).permit(:name, :nature, :amount, :date, :notes)
      account_param = params[:forecast_item]
      return permitted unless account_param.respond_to?(:key?) && account_param.key?(:account_id)

      account = forecast_accounts.find { |candidate| candidate.id == account_param[:account_id].to_s }
      permitted.merge(account_id: account&.id, currency: account&.currency)
    end
end
