# Fulas Bank: FlowVista's "cash cushion": how many months of ordinary
# spending the money in the user's current and savings accounts would cover.
# Three to six months is the usual advice for an emergency fund.
class CashCushion
  RECOMMENDED_MONTHS = 3..6
  # Fulas Bank: how many finished months the typical spending looks at.
  RECENT_MONTHS = 12

  attr_reader :family, :user, :today

  def initialize(family, user:, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  def currency
    family.currency
  end

  # Cash in the depository accounts the user reaches, in the family currency.
  def cash
    @cash ||= Money.new(accounts.sum { |account| converted_balance(account) }, currency)
  end

  # A typical month's spending. Fulas Bank: the last twelve finished months
  # with history, without the highest and the lowest (TrimmedMonthlyAverage),
  # so a month with a big purchase, or an old month with only some accounts
  # imported, does not move it much. (It was the median of every month on
  # record, which those old half-empty months pulled far down.)
  def monthly_expense
    @monthly_expense ||= Money.new(TrimmedMonthlyAverage.mean(month_totals), currency)
  end

  # The spending of each month averaged, newest first.
  def month_totals
    @month_totals ||= begin
      start = history_start
      statement = IncomeStatement.new(family, user: user)

      (1..RECENT_MONTHS).map { |back| today.beginning_of_month << back }
                        .select { |month| start && month >= start.beginning_of_month }
                        .map { |month| month_expense(statement, month) }
    end
  end

  # Months covered, to one decimal; nil without spending to compare with.
  def months
    return unless monthly_expense.amount.positive?

    (cash.amount / monthly_expense.amount).round(1)
  end

  # :low under the recommended range, :ok within it, :high above it.
  def level
    return unless months

    if months < RECOMMENDED_MONTHS.min
      :low
    elsif months <= RECOMMENDED_MONTHS.max
      :ok
    else
      :high
    end
  end

  private
    # The month's spending, counted as the Resumen counts it. The scope
    # filters the month (`date_range` alone does not).
    def month_expense(statement, month)
      period = Period.custom(start_date: month, end_date: month.end_of_month)
      scope = family.transactions.visible.excluding_pending.in_period(period)
      statement.totals(transactions_scope: scope, date_range: period.date_range).expense_money.amount.to_d
    end

    # The first movement in the user's accounts: months before it are not
    # months without spending, just months without data.
    def history_start
      family.entries.where(entryable_type: "Transaction", account_id: family.accounts.accessible_by(user).select(:id)).minimum(:date)
    end

    def accounts
      @accounts ||= family.accounts.visible.included_in_reports.accessible_by(user).where(accountable_type: "Depository").to_a
    end

    def converted_balance(account)
      return account.balance.to_d if account.currency == currency

      account.balance_money.exchange_to(currency).amount
    rescue Money::ConversionError
      account.balance.to_d
    end
end
