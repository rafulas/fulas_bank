module ForecastsHelper
  # An expected amount from the user's side: income with a plus sign, spending
  # with a minus sign.
  def forecast_signed_amount(amount, currency)
    money = Money.new(amount.to_d.abs, currency)
    amount.to_d.negative? ? "−#{format_money(money)}" : "+#{format_money(money)}"
  end
end
