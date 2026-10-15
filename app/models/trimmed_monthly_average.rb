# Fulas Bank: the "media acotada" the forecast's "Gastos varios" and the
# budget's suggested amounts both use, written once.
#
# For a month it takes:
#   - the same month in the last three years that have already finished (for
#     October: the last three Octobers), and
#   - the last six finished months,
# drops the highest and the lowest of those values and averages the rest, so
# one unusual month does not move the result much.
module TrimmedMonthlyAverage
  SAME_MONTH_YEARS = 3
  RECENT_MONTHS = 6

  module_function

  # The months averaged for `month`, newest first, given today's date.
  #
  # @param month [Date] the first day of the month to estimate
  # @param today [Date]
  # @return [Array<Date>] first days of the sample months
  def sample_months(month, today:)
    current_month = today.beginning_of_month
    same = []
    years_back = 1

    while same.size < SAME_MONTH_YEARS
      candidate = month << (12 * years_back)
      same << candidate if candidate < current_month
      years_back += 1
    end

    recent = (1..RECENT_MONTHS).map { |back| current_month << back }
    (same + recent).uniq
  end

  # One value fewer at each end, once there are at least three to choose from.
  def trimmed(values)
    return values if values.size < 3

    values.sort[1..-2]
  end

  # The trimmed mean, rounded to cents; zero with no values.
  #
  # @param values [Array<Numeric>]
  # @return [BigDecimal]
  def mean(values)
    return BigDecimal("0") if values.empty?

    kept = trimmed(values)
    (kept.sum.to_d / kept.size).round(2)
  end
end
