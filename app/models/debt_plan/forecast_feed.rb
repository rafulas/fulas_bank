# Fulas Bank: the debt plan as the Forecast sees it ("Plan Reducc Deuda"
# feeding the forecast). Each month, one line per loan with its payment on
# the loan's day (the usual payment plus its share of the snowball), and one
# line with that month's one-off contributions on their own date.
#
# The recurring movements linked to the loans stop where the plan starts
# (next month); this month's are still the real ones.
DebtPlan::ForecastFeed = Data.define(:schedule, :account_id, :replaced_recurring_ids, :loan_names, :payment_days, :extra_payments) do
  def starts_on
    schedule.start
  end

  def replaces?(series)
    replaced_recurring_ids.include?(series.id)
  end

  # [ [date, loan name, amount], ... ] for the regular payments.
  def payments
    schedule.months.flat_map do |month|
      month.payments.filter_map do |key, amount|
        regular = amount - month.additional.fetch(key, 0)
        next unless regular.positive?

        [ day_in(month.date, payment_days.fetch(key, 1)), loan_names.fetch(key, key), regular.round(2) ]
      end
    end
  end

  # [ [date, names, amount], ... ] for the one-off contributions.
  def contributions
    schedule.months.filter_map do |month|
      total = month.additional.values.sum(BigDecimal(0))
      next unless total.positive?

      this_month = extra_payments.select { |payment| payment.dates.any? { |date| date.beginning_of_month == month.date } }
      date = this_month.flat_map(&:dates).select { |each| each.beginning_of_month == month.date }.min || month.date
      [ date, this_month.map(&:display_name).uniq.to_sentence, total.round(2) ]
    end
  end

  private
    def day_in(month, day)
      month.change(day: day.to_i.clamp(1, month.end_of_month.day))
    end
end
