# Fulas Bank: one budget seen on its own, as Bilance's budget screen: the
# month's spending day by day against its amount, what is left per day and
# the daily average, the spending by category, the last six months with
# their average, the month's movements and the amounts set from each month.
class BudgetGroup::Detail
  HISTORY_MONTHS = 6

  CategorySpending = Data.define(:category, :amount, :share)

  HistoryMonth = Data.define(:month, :spent, :limit) do
    def over?
      limit.positive? && spent > limit
    end

    # Spending against the amount (or against the largest month without
    # one), from 0 to 1, for the bar.
    def share(scale)
      scale.positive? ? [ spent / scale, 1 ].min : 0
    end
  end

  attr_reader :group, :month_budget, :today

  def initialize(group, month_budget:, today: Date.current)
    @group = group
    @month_budget = month_budget
    @today = today
  end

  def month
    month_budget.month
  end

  def limit
    group.limit_for(month)
  end

  # Also in a month without an amount.
  def spent
    @spent ||= [ category_amounts.values.sum, 0 ].max
  end

  def remaining
    limit - spent
  end

  def over?
    remaining.negative?
  end

  def share
    limit.positive? ? [ (spent / limit * 100).round, 0 ].max : 0
  end

  def current_month?
    month == today.beginning_of_month
  end

  # The days still to come this month, today included (all of a future
  # month, none of a past one).
  def days_left
    return 0 if month.end_of_month < today
    return month.end_of_month.day if month > today

    (month.end_of_month - today).to_i + 1
  end

  # «Restante al día»: what is left spread over the days to come.
  def remaining_per_day
    days_left.positive? && remaining.positive? ? (remaining / days_left).round(2) : 0.to_d
  end

  def days_gone
    return 0 if month > today
    return month.end_of_month.day if month.end_of_month < today

    today.day
  end

  # «Gasto medio diario» so far.
  def daily_average
    days_gone.positive? ? (spent / days_gone).round(2) : 0.to_d
  end

  # Spending ahead of the month's pace (or over the amount): shown in red.
  def ahead_of_pace?
    return over? unless current_month?

    over? || (limit.positive? && spent / limit > days_gone.to_d / month.end_of_month.day)
  end

  # The months a future limit can start on: this one and the next five years.
  def limit_months
    (0..60).map { |ahead| today.beginning_of_month >> ahead }
  end

  # The pace chart's data (as MonthPlan#budget_pace), or nil for a future
  # month or a month without an amount.
  def pace
    return if month > today || !limit.positive?

    last_day = [ month.end_of_month, today ].min
    daily = month_budget.daily_spending(last_day, group.expanded_category_ids)
    running = 0
    spent_by_day = (month..last_day).map { |date| (running += daily.fetch(date, 0).to_d).to_f.round(2) }

    { days: month.end_of_month.day, total: limit.to_f.round(2), spent: spent_by_day, today: (today.day if current_month?) }
  end

  # What each of the budget's categories spent this month, the largest first.
  def by_category
    @by_category ||= begin
      amounts = category_amounts.select { |_, amount| amount.positive? }
      total = amounts.values.sum
      categories = group.family.categories.where(id: amounts.keys).index_by { |category| category.id.to_s }

      amounts.filter_map do |id, amount|
        CategorySpending.new(category: categories[id], amount: amount, share: total.positive? ? amount / total : 0) if categories[id]
      end.sort_by { |row| -row.amount }
    end
  end

  # The month and the five before it, newest first.
  def history
    @history ||= begin
      months = (0...HISTORY_MONTHS).map { |back| month << back }
      spent_by_month = month_budget.monthly_spending(group, months)
      months.map { |item| HistoryMonth.new(month: item, spent: spent_by_month.fetch(item, 0.to_d), limit: group.limit_for(item)) }
    end
  end

  # What the bars of the history are measured against.
  def history_scale
    history.map { |row| [ row.spent, row.limit ].max }.max.to_d
  end

  # The average of the finished months shown (the current one is still
  # being spent).
  def history_average
    finished = history.select { |row| row.month < today.beginning_of_month }
    finished.any? ? (finished.sum(&:spent) / finished.size).round(2) : 0.to_d
  end

  def entries
    @entries ||= month_budget.entries_for(group).to_a
  end

  def category_amounts
    @category_amounts ||= month_budget.spending_by_category(group.expanded_category_ids)
  end

  # The amounts set, newest first: each holds from its month until the next.
  def limits
    group.limits.reverse
  end
end
