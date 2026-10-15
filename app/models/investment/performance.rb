# Fulas Bank: how an investment account has done, like the bank's own
# "Evolución y rentabilidad": what it is worth, what was put in and what was
# gained, for any period.
#
# - Value of each day: the account's daily balance (what the app already
#   calculates from purchases, prices and the values typed by hand).
# - Put in ("aportado"): the money movements of the account (money in minus
#   money out). Buying and selling inside the account does not count, nor do
#   valuations typed by hand.
# - Gained in a period: value at the end − value at the start − what was put
#   in during the period.
# - Return of a period (Modified Dietz, the usual way banks show it): the gain
#   divided by the value at the start plus each contribution weighted by the
#   share of the period it was invested.
#
# The chart (investment-performance-chart) repeats the last two calculations
# in the browser for whatever period is chosen, from #series.
class Investment::Performance
  Summary = Data.define(:start_date, :end_date, :value, :contributed, :gain, :return_ratio)

  attr_reader :account, :today

  def initialize(account, today: Date.current)
    @account = account
    @today = today
  end

  def currency
    account.currency
  end

  # One point per day with a balance, oldest first:
  # { date:, value:, flow: } where flow is the money put in that day.
  def series
    @series ||= balances.map do |date, value|
      { date: date, value: value.to_d, flow: flows.fetch(date, 0).to_d }
    end
  end

  def any?
    series.size > 1
  end

  def first_date
    series.first&.dig(:date)
  end

  # @param range [Range<Date>] the period (clipped to the account's history)
  # @return [Summary, nil] nil without history in that period
  def summary(range)
    points = series.select { |point| range.cover?(point[:date]) }
    return if points.empty?

    # The value at the start is the one before the period's first day, so a
    # contribution on that first day counts as put in, not as start value.
    before = series.reverse.find { |point| point[:date] < points.first[:date] }
    start_value = before ? before[:value] : 0.to_d
    start_date = before ? before[:date] : points.first[:date] - 1
    end_point = points.last

    contributed = points.sum { |point| point[:flow] }
    gain = end_point[:value] - start_value - contributed

    days = (end_point[:date] - start_date).to_i
    weighted = points.sum do |point|
      days.positive? ? point[:flow] * (end_point[:date] - point[:date]).to_i / days : 0
    end
    base = start_value + weighted

    Summary.new(
      start_date: points.first[:date],
      end_date: end_point[:date],
      value: money(end_point[:value]),
      contributed: money(contributed),
      gain: money(gain),
      return_ratio: (base.positive? ? (gain / base).to_f : nil)
    )
  end

  def year_to_date
    summary(today.beginning_of_year..today)
  end

  # The last money movements of the account, newest first.
  def recent_movements(limit: 5)
    account.entries.where(entryable_type: "Transaction", excluded: false)
           .excluding_split_parents.order(date: :desc, created_at: :desc).limit(limit)
  end

  private
    def money(amount)
      Money.new(amount, currency)
    end

    # [[date, value]] of the account's daily balances in its own currency.
    def balances
      account.balances.where(currency: currency, date: ..today).order(:date).pluck(:date, :end_balance)
    end

    # { date => money put in that day }
    def flows
      @flows ||= account.entries
                        .where(entryable_type: "Transaction", excluded: false, date: ..today)
                        .excluding_split_parents
                        .group(:date)
                        .sum(:amount)
                        .transform_values { |amount| -amount.to_d }
    end
end
