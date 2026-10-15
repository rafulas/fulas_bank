# Fulas Bank: the summary shown in the movements list where a month starts,
# like Bilance's "Resumen de mayo": what was spent and earned that month,
# how far over (or under) its budget, and the savings rate.
#
# It follows the list's filters: `scope` is the list's own search (accounts,
# categories, dates...), cut here to the calendar month. Transfers and
# excluded movements do not count as spending or income.
class Transaction::MonthSummary
  attr_reader :family, :month, :scope, :user

  def initialize(family, month:, scope:, user: nil)
    @family = family
    @month = month.beginning_of_month
    @scope = scope
    @user = user
  end

  def spent
    Money.new(totals[:expense], family.currency)
  end

  def income
    Money.new(totals[:income], family.currency)
  end

  # Income minus spending: what the month left (negative when it cost more).
  def net
    income - spent
  end

  # Share of the income that was not spent, as a whole percentage; zero when
  # the month earned nothing or spent more than it earned.
  def savings_rate
    return 0 unless income.amount.positive?

    [ ((income.amount - spent.amount) / income.amount * 100).round, 0 ].max
  end

  # How much the month's spending went over its budget (positive) or stayed
  # under it (negative), or nil when the month has no budget set.
  def budget_difference
    return @budget_difference if defined?(@budget_difference)

    @budget_difference = if budget && budget.budgeted_spending.to_d.positive?
      Money.new(budget.actual_spending.to_d - budget.budgeted_spending.to_d, budget.currency)
    end
  end

  def over_budget?
    budget_difference.present? && budget_difference.amount.positive?
  end

  private
    def totals
      @totals ||= begin
        row = scope.where(entries: { date: month..month.end_of_month, excluded: false })
                   .where(Transaction.counts_by_kind_sql)
                   .joins(ActiveRecord::Base.sanitize_sql_array([
                     "LEFT JOIN exchange_rates month_rates ON (month_rates.date = entries.date AND month_rates.from_currency = entries.currency AND month_rates.to_currency = ?)",
                     family.currency
                   ]))
                   .pick(
                     Arel.sql("COALESCE(SUM(CASE WHEN entries.amount >= 0 THEN entries.amount * COALESCE(month_rates.rate, 1) ELSE 0 END), 0)"),
                     Arel.sql("COALESCE(SUM(CASE WHEN entries.amount < 0 THEN -entries.amount * COALESCE(month_rates.rate, 1) ELSE 0 END), 0)")
                   )

        { expense: row[0].to_d, income: row[1].to_d }
      end
    end

    # The household budget of the period the month starts in, or the user's
    # own when budgets are personal. Never created here: a list does not
    # start budgets.
    def budget
      return @budget if defined?(@budget)

      start_date, = Budget.period_for(month, family: family)
      candidates = family.budgets.where(start_date: start_date).to_a
      @budget = candidates.find { |candidate| candidate.user_id.nil? } || candidates.find { |candidate| candidate.user_id == user&.id }
      @budget&.current_user = user
      @budget = nil if @budget && !@budget.initialized?
      @budget
    end
end
