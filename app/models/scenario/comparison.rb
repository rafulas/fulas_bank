# Fulas Bank: the forecast with and without a scenario, month by month: what
# comes in, what goes out and the result of each month (from the user's
# side, in the family's currency), and the total balance at its end.
#
# Only the accounts that add up in the forecast's totals count, and a
# recurring transfer between two of them is neither income nor spending.
class Scenario::Comparison
  Row = Data.define(:month, :base_income, :base_spending, :income, :spending, :base_total, :total) do
    def base_net
      base_income - base_spending
    end

    def net
      income - spending
    end

    def net_difference
      net - base_net
    end

    def total_difference
      total - base_total
    end
  end

  attr_reader :base, :scenario_forecast, :scenario

  def initialize(base:, scenario_forecast:)
    @base = base
    @scenario_forecast = scenario_forecast
    @scenario = scenario_forecast.scenario
  end

  def currency
    base.currency
  end

  def rows
    @rows ||= begin
      base_totals = month_totals(base)
      totals = month_totals(scenario_forecast)

      months.map do |month|
        day = [ month.end_of_month, base.through ].min
        Row.new(month: month,
                base_income: base_totals[month][:income], base_spending: base_totals[month][:spending],
                income: totals[month][:income], spending: totals[month][:spending],
                base_total: base.total_on(day).amount, total: scenario_forecast.total_on(day).amount)
      end
    end
  end

  # The months from the one the scenario starts in: where it shows.
  def changed_rows
    start = scenario.starts_on&.beginning_of_month
    return [] unless start

    rows.select { |row| row.month >= start }
  end

  # How much better (or worse) each month ends, on average, once the changes
  # are in place: from the month after the first change, so a one-off (a
  # loan's payoff) does not weigh on it.
  def monthly_difference
    later = changed_rows.drop(1)
    return if later.empty?

    later.sum(&:net_difference) / later.size
  end

  # The difference in the total balance on the forecast's last day.
  def final_difference
    scenario_forecast.total_on(base.through).amount - base.total_on(base.through).amount
  end

  # The first month that ends no worse than without the scenario, after one
  # that ended worse: when a one-off cost (a loan's payoff) has paid for
  # itself. Nil when it never ends worse, or never catches up.
  def break_even_month
    behind = false
    rows.each do |row|
      if row.total_difference.negative?
        behind = true
      elsif behind
        return row.month
      end
    end

    nil
  end

  def ever_behind?
    rows.any? { |row| row.total_difference.negative? }
  end

  # The chart: today and each month's end, with and without the scenario.
  def chart_data
    points = [ { date: base.today.iso8601, base: base.total_on(base.today).amount.to_f, scenario: scenario_forecast.total_on(base.today).amount.to_f } ]
    rows.each do |row|
      day = [ row.month.end_of_month, base.through ].min
      next if day <= base.today

      points << { date: day.iso8601, base: row.base_total.to_f, scenario: row.total.to_f }
    end
    points
  end

  private
    def months
      list = []
      month = base.today.beginning_of_month
      while month <= base.through
        list << month
        month = month.next_month
      end
      list
    end

    # { month => { income:, spending: } } for the lines that count.
    def month_totals(forecast)
      active = forecast.active_flows
      transfers = transfer_keys(active)
      counted = forecast.counted_accounts

      active.each_with_object(Hash.new { |hash, month| hash[month] = { income: 0.to_d, spending: 0.to_d } }) do |flow, totals|
        next if flow.key && transfers.include?([ flow.key, flow.date ])
        next if flow.account && !counted.include?(flow.account)

        amount = forecast.user_amount(flow).amount
        bucket = totals[flow.date.beginning_of_month]
        amount.positive? ? bucket[:income] += amount : bucket[:spending] -= amount
      end
    end

    # A recurring transfer shows as two lines with the same key and day, one
    # out of an account and one into another.
    def transfer_keys(flows)
      flows.select { |flow| flow.source == :recurring && flow.key && flow.account }
           .group_by { |flow| [ flow.key, flow.date ] }
           .select { |_, lines| lines.any?(&:inflow?) && lines.any? { |line| !line.inflow? } }
           .keys.to_set
    end
end
