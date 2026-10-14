# Changes to the forecast lines the app works out by itself (see
# ForecastAdjustment), made from the Forecast table: edit a line, leave it
# out, or bring it back as it was.
class ForecastAdjustmentsController < ApplicationController
  before_action :require_valid_key

  # The table sends the line's own values so the form can show them; they are
  # only displayed and prefilled, never saved unless the user submits them.
  def edit
    @adjustment = Current.family.forecast_adjustments.find_or_initialize_by(key: key)
    @original = {
      date: parse_date(params[:date]),
      amount: parse_amount(params[:amount]),
      name: params[:name].to_s.first(200)
    }
    @adjustment.date ||= @original[:date]
    @adjustment.amount ||= @original[:amount]
    @adjustment.name = @adjustment.name.presence || @original[:name]
  end

  def update
    adjustment = Current.family.forecast_adjustments.find_or_initialize_by(key: key)
    adjustment.assign_attributes(adjustment_params)

    if adjustment.save
      redirect_back_or_to forecast_path, notice: t(adjustment.skipped? ? ".skipped" : ".success")
    else
      redirect_back_or_to forecast_path, alert: adjustment.errors.full_messages.to_sentence
    end
  end

  # Back to the line the app works out, with no change.
  def destroy
    Current.family.forecast_adjustments.find_by(key: key)&.destroy!
    redirect_back_or_to forecast_path, notice: t(".success")
  end

  private
    def key
      params.dig(:forecast_adjustment, :key).presence || params[:key]
    end

    def require_valid_key
      head :not_found unless ForecastAdjustment.valid_key?(key)
    end

    def adjustment_params
      params.require(:forecast_adjustment).permit(:date, :amount, :name, :skipped)
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def parse_amount(value)
      amount = BigDecimal(value.to_s).abs
      amount if amount.positive?
    rescue ArgumentError
      nil
    end
end
