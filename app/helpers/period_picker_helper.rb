# Fulas Bank: what the period picker (shared/_period_picker) needs from the
# family's data.
module PeriodPickerHelper
  # The day of the month the main income comes in (the salary), for the
  # "since the last payday" shortcut; nil without a recurring income.
  def period_picker_payday
    return @period_picker_payday if defined?(@period_picker_payday)

    income = Current.family&.recurring_transactions&.active&.typed_income&.order(:amount)&.first
    @period_picker_payday = income&.expected_day_of_month
  end
end
