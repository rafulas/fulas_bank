# Fulas Bank: the figures on Inicio's «Libre en este periodo» card, after
# FlowVista's: what is left of the period's income, how many days remain,
# what is spent a day, how that compares with the same point of the period
# before, and the saving rate against the usual 20 % guideline.
class FreeCash
  # Share of income worth keeping, the 50/30/20 rule's figure.
  SAVING_TARGET = 20

  attr_reader :income, :expense, :period, :previous_expense, :today

  # `previous_expense` is what had been spent by the same day of the period
  # before (nil when there is nothing to compare with).
  def initialize(income:, expense:, period:, previous_expense: nil, today: Date.current)
    @income = income
    @expense = expense
    @period = period
    @previous_expense = previous_expense
    @today = today
  end

  # The days before this period's that match the ones gone by in it, for
  # `previous_expense`.
  def self.comparison_period(period, today: Date.current)
    elapsed = elapsed_days(period, today)
    return if elapsed.zero?

    start_date = period.start_date - period.days
    Period.custom(start_date: start_date, end_date: start_date + elapsed - 1)
  end

  def self.elapsed_days(period, today)
    last_day = [ period.end_date, today ].min
    return 0 if last_day < period.start_date

    (last_day - period.start_date).to_i + 1
  end

  def free
    income - expense
  end

  def ratio
    income.amount.positive? ? expense.amount / income.amount : nil
  end

  # Share of income kept, in percent; nil without income.
  def saving_rate
    ratio && ((1 - ratio) * 100).round(1)
  end

  def meets_target?
    saving_rate.present? && saving_rate >= SAVING_TARGET
  end

  def current?
    period.date_range.cover?(today)
  end

  # Days left in the period, today included; nil once it is over.
  def days_left
    (period.end_date - today).to_i + 1 if current?
  end

  def elapsed_days
    self.class.elapsed_days(period, today)
  end

  def daily_average
    return if elapsed_days.zero?

    Money.new(expense.amount / elapsed_days, expense.currency)
  end

  # What can still be spent each remaining day without eating into the
  # income still to come; nil when nothing is left or the period is over.
  def per_day_left
    return unless days_left && free.amount.positive?

    Money.new(free.amount / days_left, free.currency)
  end

  # Percent change in spending against the same point of the period before.
  def expense_change
    return unless previous_expense&.amount&.positive?

    ((expense.amount - previous_expense.amount) / previous_expense.amount * 100).round
  end
end
