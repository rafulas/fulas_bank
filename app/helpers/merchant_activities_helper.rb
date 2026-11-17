# Fulas Bank: links of the "Comercios" tab that keep the period chosen.
module MerchantActivitiesHelper
  def merchant_activity_period_params(period)
    period.key.present? ? { period: period.key } : { start_date: period.start_date, end_date: period.end_date }
  end

  def merchant_activity_link(name, period)
    merchant_activity_path(merchant_activity_period_params(period).merge(name: name))
  end
end
