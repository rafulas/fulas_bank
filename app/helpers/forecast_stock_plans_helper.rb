# Fulas Bank: amounts and share counts of a «Plan de acciones», with a dash
# for what cannot be worked out yet.
module ForecastStockPlansHelper
  def stock_plan_money(plan, amount)
    amount.nil? ? "—" : format_money(Money.new(amount, plan.currency))
  end

  def stock_plan_shares(count)
    return "—" if count.nil?

    number_with_precision(count, precision: 2, strip_insignificant_zeros: true, delimiter: ".", separator: ",")
  end
end
