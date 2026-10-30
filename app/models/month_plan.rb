# Fulas Bank: the "Planes" screen, like Bilance's: for one month,
#   - the budget: spent so far against the total, day by day, and each
#     budget (MonthBudget: a name and the categories it groups) with what
#     is left (or how far over);
#   - the recurring movements: what has been paid and what is still to pay,
#     the balance left after them, a calendar with each day's payments, and
#     the list by kind with a tick on the ones already paid;
#   - and the recurring movements that come later than this month (yearly
#     taxes, insurance renewals...).
#
# It reads the budget and the recurring payments the app already keeps; it
# creates neither.
class MonthPlan
  FUTURE_LIMIT = 12

  # Kinds of recurring movement, in the order the screen lists them. Fulas
  # Bank: fixed, bills and subscriptions (see RecurringTransaction::Kind),
  # with the fixed income apart.
  GROUPS = {
    "income" => "income",
    "installment" => "fixed",
    "transfer" => "fixed",
    "other" => "fixed",
    "bill" => "bills",
    "subscription" => "subscriptions"
  }.freeze

  # A budget of the month (BudgetGroup), its amount and what it has spent.
  BudgetRow = Data.define(:group, :budgeted, :spent) do
    def name
      group.name
    end

    # The category whose icon and colour it shows.
    def category
      group.display_category
    end

    def available
      budgeted - spent
    end

    def over?
      available.negative?
    end

    def share
      budgeted.positive? ? spent.to_d / budgeted.to_d : 0
    end
  end

  # One payment of a recurring series this month.
  Payment = Data.define(:occurrence, :series, :date, :amount, :paid, :state) do
    def income?
      series.typed_income? || series.amount.to_d.negative?
    end

    def name
      series.display_name
    end
  end

  Group = Data.define(:key, :payments) do
    def total
      payments.sum(&:amount)
    end

    def paid_total
      payments.select(&:paid).sum(&:amount)
    end
  end

  Upcoming = Data.define(:series, :date, :amount)

  # Fulas Bank: a payment still to make (or income still to come), for
  # Inicio's "next payments" and the timeline.
  # `occurrence` is the stored payment, to open it (nil for a later one).
  NextPayment = Data.define(:series, :date, :amount, :state, :occurrence) do
    def income?
      series.typed_income? || series.amount.to_d.negative?
    end

    def name
      series.display_name
    end
  end

  # The next `limit` recurring movements not yet settled: overdue ones from
  # this month first, then this month's and the next month's, then the
  # series whose next date comes later.
  def self.next_payments(family, user:, today: Date.current, limit: 5)
    this_month = new(family, user: user, month: today, today: today)
    next_month = new(family, user: user, month: today.next_month, today: today)

    pending = (this_month.payments + next_month.payments).reject(&:paid).map do |payment|
      NextPayment.new(series: payment.series, date: payment.date, amount: payment.amount, state: payment.state,
                      occurrence: payment.occurrence)
    end
    seen = pending.map { |payment| payment.series.id }.to_set
    later = next_month.upcoming.reject { |item| seen.include?(item.series.id) }.map do |item|
      NextPayment.new(series: item.series, date: item.date, amount: item.amount, state: :expected, occurrence: nil)
    end

    (pending.sort_by(&:date) + later).first(limit)
  end

  attr_reader :family, :user, :month, :today

  def initialize(family, user:, month: Date.current, today: Date.current)
    @family = family
    @user = user
    @month = month.beginning_of_month
    @today = today
  end

  def currency
    family.currency
  end

  def end_of_month
    month.end_of_month
  end

  def current_month?
    month == today.beginning_of_month
  end

  # ---- Budget ----

  # The month's budgets (see MonthBudget).
  def month_budget
    @month_budget ||= MonthBudget.new(family, user: user, month: month)
  end

  # The budgets with an amount this month, the largest first.
  def budget_rows
    @budget_rows ||= month_budget.budgeted_groups.map do |group|
      BudgetRow.new(group: group, budgeted: group.limit_for(month), spent: month_budget.spent(group))
    end.sort_by { |row| -row.budgeted }
  end

  # Fulas Bank: the budget a movement in `category` counts against, or nil
  # when it is in none with an amount this month.
  def budget_row_for(category)
    return if category.nil?

    budget_rows.find { |row| row.group.covers?(category) }
  end

  def budget_total
    money(budget_rows.sum(&:budgeted))
  end

  def budget_spent
    money(budget_rows.sum(&:spent))
  end

  def budget_share
    budget_total.amount.positive? ? (budget_spent.amount / budget_total.amount * 100).round : 0
  end

  # Share of the month gone by (all of it for a past month).
  def elapsed_share
    return 1 if end_of_month < today
    return 0 if month > today

    (today - month + 1).to_d / month.end_of_month.day
  end

  # Spending ahead of the month's pace (or over the budget): shown in red.
  def ahead_of_pace?(row)
    row.over? || row.share > elapsed_share
  end

  # Cumulative spending in the budgeted categories, day by day up to today,
  # for the chart.
  def budget_series
    return nil if budget_rows.empty?

    last_day = [ end_of_month, today ].min
    return nil if last_day < month

    daily = budget_daily_spending(last_day)
    running = 0
    values = (month..last_day).map do |date|
      running += daily.fetch(date, 0).to_d
      { date: date, value: money(running) }
    end

    Series.from_raw_values(values, interval: "1 day")
  end

  # Fulas Bank: the spending pace against the budget, for the Planes chart:
  # what has been spent day by day and the budget spread evenly over the
  # month (the line spending should stay under).
  def budget_pace
    return nil if budget_rows.empty? || month > today

    last_day = [ end_of_month, today ].min
    daily = budget_daily_spending(last_day)
    running = 0
    spent = (month..last_day).map { |date| (running += daily.fetch(date, 0).to_d).to_f.round(2) }

    { days: end_of_month.day, total: budget_rows.sum(&:budgeted).to_f.round(2), spent: spent,
      today: (today.day if current_month?) }
  end

  # Where spending should be today if the budget were spent evenly, and how
  # far above (positive) or below it the month goes.
  def budget_pace_expected
    money((budget_rows.sum(&:budgeted).to_d * elapsed_share).round(2))
  end

  def budget_pace_gap
    budget_spent - budget_pace_expected
  end

  # ---- Recurring movements ----

  def payments
    @payments ||= occurrences.map do |occurrence|
      series = occurrence.recurring_transaction
      paid = occurrence.paid?
      amount = paid && occurrence.confirmed_allocated.to_d.positive? ? occurrence.confirmed_allocated.to_d : occurrence.resolved_expected_amount.to_d
      Payment.new(occurrence: occurrence, series: series, date: occurrence.effective_due_on, amount: amount, paid: paid, state: payment_state(occurrence))
    end.sort_by { |payment| [ payment.date, payment.name.to_s ] }
  end

  def groups
    @groups ||= payments.group_by { |payment| GROUPS.fetch(payment.series.bill_type.to_s, "fixed") }
                        .map { |key, list| Group.new(key: key, payments: list) }
                        .sort_by { |group| GROUPS.values.uniq.index(group.key) }
  end

  def outgoing
    payments.reject(&:income?)
  end

  def paid_total
    money(outgoing.select(&:paid).sum(&:amount))
  end

  def pending_total
    money(outgoing.reject(&:paid).sum(&:amount))
  end

  def paid_share
    total = paid_total.amount + pending_total.amount
    total.positive? ? (paid_total.amount / total * 100).round : 0
  end

  # The balance of the movements panel's accounts once this month's pending
  # payments and income have gone through.
  def balance_after_recurring
    pending_income = payments.select(&:income?).reject(&:paid).sum(&:amount)
    Transaction::Panel.new(family, user: user, today: today).accounts_total + money(pending_income) - pending_total
  end

  # { date => [Payment] } for the calendar.
  def payments_by_day
    @payments_by_day ||= payments.group_by(&:date)
  end

  # Recurring movements whose next payment comes after this month, soonest
  # first: what is coming that this month does not show.
  def upcoming
    @upcoming ||= begin
      in_month = payments.map { |payment| payment.series.id }.to_set
      series_list.reject { |series| in_month.include?(series.id) }.filter_map do |series|
        date = series.schedule.first_occurrence_after(end_of_month)
        Upcoming.new(series: series, date: date, amount: series.amount.to_d.abs) if date
      end.sort_by(&:date).first(FUTURE_LIMIT)
    end
  end

  private
    def money(amount)
      Money.new(amount, currency)
    end

    def budget_daily_spending(last_day)
      month_budget.daily_spending(last_day, budget_rows.flat_map { |row| row.group.expanded_category_ids }.uniq)
    end

    def series_list
      @series_list ||= family.recurring_transactions
                             .accessible_by(user)
                             .where(status: "active")
                             .includes(:merchant, :category, :recurrence_rules)
                             .to_a
    end

    def occurrences
      family.recurring_occurrences
            .where(recurring_transaction_id: series_list.map(&:id))
            .where(due_on: month..end_of_month)
            .where.not(status: "skipped")
            .includes(recurring_transaction: [ :merchant, :category ])
            .to_a
            .reject { |occurrence| past_series_end?(occurrence) }
    end

    # Fulas Bank: a payment dated after its series ended (an unpaid row left
    # from before the end date was set) is not owed.
    def past_series_end?(occurrence)
      return false if occurrence.paid?

      series = occurrence.recurring_transaction
      series.ends_on_date? && series.end_on.present? && occurrence.effective_due_on > series.end_on
    end

    # :paid, :today, :overdue (its date passed without payment) or :expected.
    def payment_state(occurrence)
      return :paid if occurrence.paid?

      date = occurrence.effective_due_on
      if date == today
        :today
      elsif date < today
        :overdue
      else
        :expected
      end
    end
end
