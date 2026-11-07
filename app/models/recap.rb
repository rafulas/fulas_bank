# Fulas Bank: the weekly and monthly recap ("Resumen de la semana",
# "Resumen de octubre"), after Bilance's. One closed (or running) week or
# month, with what Category::Analysis already works out for the Resumen,
# set against the period before:
#   - spent, earned, the result and the savings rate, and how they moved;
#   - the categories that moved the most;
#   - the biggest expenses;
#   - how the total balance went over the period;
#   - for a month, its budgets and recurring payments (MonthPlan);
#   - for the last week, the payments coming the week after.
#
# A week runs Monday to Sunday. A month follows the family's month start
# day, and is named after the calendar month it starts in.
#
# Identified in URLs as "2026-10" (month) or "2026-W44" (ISO week).
class Recap
  KINDS = %w[week month].freeze
  TOP_CHANGES = 3
  BIGGEST_EXPENSES = 5
  # How many days after it closes a recap is offered on Inicio.
  FRESH_DAYS = { "week" => 3, "month" => 5 }.freeze
  # A category change smaller than this is not worth a line.
  MIN_CHANGE = 1

  MONTH_PARAM = /\A(?<year>\d{4})-(?<month>\d{2})\z/
  WEEK_PARAM = /\A(?<year>\d{4})-W(?<week>\d{2})\z/

  Change = Data.define(:id, :name, :color, :amount, :previous) do
    def delta
      amount - previous
    end

    def up?
      delta.positive?
    end
  end

  attr_reader :family, :user, :kind, :start_date, :end_date, :today

  class << self
    def for(family, user:, kind:, date:, today: Date.current)
      kind = kind.to_s
      raise ArgumentError, "Invalid recap kind: #{kind}" unless kind.in?(KINDS)

      start_date, end_date = bounds(family, kind, date)
      new(family, user: user, kind: kind, start_date: start_date, end_date: end_date, today: today)
    end

    # nil when the param is not a month or week this app can show.
    def from_param(family, param, user:, today: Date.current)
      if (match = MONTH_PARAM.match(param.to_s))
        month = Date.new(match[:year].to_i, match[:month].to_i, 1)
        self.for(family, user: user, kind: "month", date: month_anchor(family, month), today: today)
      elsif (match = WEEK_PARAM.match(param.to_s))
        self.for(family, user: user, kind: "week", date: Date.commercial(match[:year].to_i, match[:week].to_i, 1), today: today)
      end
    rescue Date::Error
      nil
    end

    # The last week or month that has already ended.
    def latest(family, user:, kind:, today: Date.current)
      current = self.for(family, user: user, kind: kind, date: today, today: today)
      current.previous
    end

    # The recaps that closed in the last few days, newest kind first (the
    # month before the week), for Inicio to point at.
    def fresh(family, user:, today: Date.current)
      KINDS.reverse.filter_map do |kind|
        recap = latest(family, user: user, kind: kind, today: today)
        recap if today - recap.end_date <= FRESH_DAYS.fetch(kind)
      end
    end

    private
      def bounds(family, kind, date)
        if kind == "week"
          [ date.beginning_of_week, date.end_of_week ]
        else
          [ family.custom_month_start_for(date), family.custom_month_end_for(date) ]
        end
      end

      # A day that falls in the family month named after `month`.
      def month_anchor(family, month)
        Date.new(month.year, month.month, [ family.month_start_day.to_i, 1 ].max.clamp(1, month.end_of_month.day))
      end
  end

  def initialize(family, user:, kind:, start_date:, end_date:, today: Date.current)
    @family = family
    @user = user
    @kind = kind
    @start_date = start_date
    @end_date = end_date
    @today = today
  end

  def week?
    kind == "week"
  end

  def month?
    kind == "month"
  end

  def to_param
    if week?
      start_date.strftime("%G-W%V")
    else
      start_date.strftime("%Y-%m")
    end
  end

  def closed?
    end_date < today
  end

  def started?
    start_date <= today
  end

  def previous
    self.class.for(family, user: user, kind: kind, date: start_date - 1.day, today: today)
  end

  # nil for the running one: there is nothing after it yet.
  def next
    following = self.class.for(family, user: user, kind: kind, date: end_date + 1.day, today: today)
    following if following.started?
  end

  def title
    if week?
      I18n.t("recaps.title.week", start: I18n.l(start_date, format: "%-d %b"), end: I18n.l(end_date, format: "%-d %b"))
    else
      I18n.t("recaps.title.month", month: I18n.l(start_date, format: "%B"))
    end
  end

  # "Octubre" / "la semana": how the text refers to the period.
  def period_name
    week? ? I18n.t("recaps.period_name.week") : I18n.l(start_date, format: "%B")
  end

  def previous_period_name
    week? ? I18n.t("recaps.period_name.previous_week") : I18n.l(previous.start_date, format: "%B")
  end

  def period
    @period ||= Period.custom(start_date: start_date, end_date: end_date)
  end

  def account_ids
    @account_ids ||= family.accounts.accessible_by(user).included_in_reports.pluck(:id)
  end

  def analysis
    @analysis ||= Category::Analysis.new(family, period: period, account_ids: account_ids, today: today)
  end

  def previous_analysis
    @previous_analysis ||= Category::Analysis.new(family, period: previous.period, account_ids: account_ids, today: today)
  end

  def currency
    family.currency
  end

  # The category rows, as in the Resumen.
  def summary
    @summary ||= Category::Summary.new(family, period: period, account_ids: account_ids)
  end

  # The same days seen as the other kind: the month a week starts in, or
  # the last week of a month (the running one, for the running month).
  def switch_kind
    if week?
      self.class.for(family, user: user, kind: "month", date: start_date, today: today)
    else
      self.class.for(family, user: user, kind: "week", date: [ end_date, today ].min, today: today)
    end
  end

  delegate :spent, :income, :net, :savings_rate, :daily_average, to: :analysis

  def any_activity?
    analysis.spending_slices.any? || analysis.income_slices.any?
  end

  # Change in percent against the previous period, nil when there is nothing
  # to compare with.
  def spent_change
    percent_change(spent.amount, previous_analysis.spent.amount)
  end

  def income_change
    percent_change(income.amount, previous_analysis.income.amount)
  end

  # The main categories whose spending moved the most against the previous
  # period, either way.
  def category_changes
    @category_changes ||= begin
      now = analysis.spending_slices.index_by(&:id)
      before = previous_analysis.spending_slices.index_by(&:id)

      (now.keys | before.keys).filter_map do |id|
        slice = now[id] || before[id]
        change = Change.new(id: id, name: slice.name, color: slice.color,
                            amount: now[id]&.amount || 0, previous: before[id]&.amount || 0)
        change if change.delta.abs >= MIN_CHANGE
      end.sort_by { |change| -change.delta.abs }.first(TOP_CHANGES)
    end
  end

  def biggest_expenses
    @biggest_expenses ||= analysis.biggest_expenses(limit: BIGGEST_EXPENSES)
  end

  # The total balance over the period (up to today).
  def balance_series
    @balance_series ||= family.balance_sheet.net_worth_series(
      period: Period.custom(start_date: start_date, end_date: [ end_date, today ].min)
    )
  end

  # Budgets and recurring payments of the month.
  def month_plan
    return unless month?

    @month_plan ||= MonthPlan.new(family, user: user, month: start_date, today: today)
  end

  # The week just closed (today falls in the next one).
  def last_closed_week?
    week? && closed? && today <= end_date + 7.days
  end

  # For the week just closed: the recurring payments due the week after.
  def coming_payments
    return [] unless last_closed_week?

    following_end = end_date + 7.days
    MonthPlan.next_payments(family, user: user, today: today, limit: 10)
             .select { |payment| payment.date <= following_end }
  end

  # The figures the written report is made from, already formatted, so the
  # text can only repeat them.
  def report_facts
    {
      period: period_name,
      previous_period: previous_period_name,
      spent: formatted(spent),
      income: formatted(income),
      net: formatted(net),
      savings_rate: "#{savings_rate} %",
      spent_change: spent_change && "#{spent_change.round} %",
      income_change: income_change && "#{income_change.round} %",
      previous_spent: formatted(previous_analysis.spent),
      previous_net: formatted(previous_analysis.net),
      top_category: analysis.spending_slices.first&.then { |slice| { name: slice.name, amount: formatted(Money.new(slice.amount, currency)) } },
      biggest_changes: category_changes.map do |change|
        { name: change.name, now: formatted(Money.new(change.amount, currency)), before: formatted(Money.new(change.previous, currency)) }
      end,
      biggest_expense: biggest_expenses.first&.then { |entry| { name: entry.name, amount: formatted(entry.amount_money) } },
      budget: month_plan&.budget_total&.amount&.positive? ? { budgeted: formatted(month_plan.budget_total), spent: formatted(month_plan.budget_spent) } : nil
    }.compact
  end

  private
    def percent_change(current, before)
      return if before.to_d.zero?

      ((current.to_d - before.to_d) / before.to_d.abs * 100)
    end

    def formatted(money)
      money.format(precision: 0)
    end
end
