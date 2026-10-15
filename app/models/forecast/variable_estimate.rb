# How much an account is expected to spend in a month on variable things
# (food, going out, fuel...): the "Gastos varios" line of each month in the
# forecast.
#
# For a month it takes, from the account's history:
#   - the same month in the last three years that have already finished (for
#     October: the last three Octobers), and
#   - the last six finished months,
# drops the highest and the lowest of those values and averages the rest (a
# trimmed mean, so one unusual month does not move the estimate much).
#
# It only uses the months the account has history for: with three months of
# movements it averages those; when older movements are imported, the same
# months of past years start counting. Nothing is stored: it is recalculated
# every time, so it follows any change to the movements, their categories or
# their type.
#
# "Variable" means movements that are neither fixed nor recurring (see
# Transaction::ExpenseClassifiable), nor transfers, nor one-off purchases, nor
# in the Excluded or Transfers categories. Only spending counts: income and
# refunds are left out, so the estimate errs on the side of caution.
class Forecast::VariableEstimate
  SAME_MONTH_YEARS = TrimmedMonthlyAverage::SAME_MONTH_YEARS
  RECENT_MONTHS = TrimmedMonthlyAverage::RECENT_MONTHS

  attr_reader :family, :accounts, :today

  def initialize(family, accounts:, today: Date.current)
    @family = family
    @accounts = accounts
    @today = today
  end

  # Expected spending (positive) of `account` in the whole of `month` (any day
  # of it), in the account's currency. Zero without history.
  def monthly(account, month)
    values = sample_months(month.beginning_of_month).filter_map do |sample|
      monthly_totals.dig(account.id, sample) || 0 if covered?(account, sample)
    end
    TrimmedMonthlyAverage.mean(values)
  end

  # What `account` has already spent on variable things in `month`, to know
  # how much of this month's estimate is still to come.
  def spent(account, month)
    (monthly_totals.dig(account.id, month.beginning_of_month) || 0).to_d
  end

  # The same estimate for all the accounts together, as one figure: what is
  # spent across them each month, averaged the same way. A month counts once
  # any of them has history.
  def combined_monthly(month)
    start = history_starts.values.compact.min
    return BigDecimal("0") unless start

    values = sample_months(month.beginning_of_month).filter_map do |sample|
      combined_total(sample) if sample >= start.beginning_of_month
    end
    TrimmedMonthlyAverage.mean(values)
  end

  def combined_spent(month)
    combined_total(month.beginning_of_month)
  end

  # The months averaged for `month`, newest first.
  def sample_months(month)
    TrimmedMonthlyAverage.sample_months(month, today: today)
  end

  private
    def combined_total(month)
      monthly_totals.values.sum { |months| months[month] || 0 }.to_d
    end

    def current_month
      today.beginning_of_month
    end

    # A month counts once the account has movements in it or before it.
    def covered?(account, month)
      start = history_starts[account.id]
      start.present? && month >= start.beginning_of_month
    end

    def history_starts
      @history_starts ||= family.entries
                                .where(account_id: accounts.map(&:id), entryable_type: "Transaction")
                                .group(:account_id)
                                .minimum(:date)
    end

    # { account_id => { month => variable spending } } since the oldest month
    # any sample can reach: the same month three finished years back.
    def monthly_totals
      @monthly_totals ||= begin
        from = current_month << (12 * SAME_MONTH_YEARS)

        rows = family.entries
                     .excluding_split_parents
                     .where(account_id: accounts.map(&:id), entryable_type: "Transaction", excluded: false, date: from..today.end_of_month)
                     .where("entries.amount > 0")
                     .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
                     .where.not(transactions: { kind: Transaction::TRANSFER_KINDS + [ "one_time" ] })
                     .where("transactions.category_id IS NULL OR transactions.category_id NOT IN (#{Category::ANALYTICS_NEUTRAL_IDS_SQL})")
                     .where.not(transactions: { id: Transfer.select(:inflow_transaction_id) })
                     .where.not(transactions: { id: Transfer.select(:outflow_transaction_id) })
                     .where(Transaction.variable_expense_sql)
                     .group(:account_id, Arel.sql("date_trunc('month', entries.date)"))
                     .sum(:amount)

        rows.each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |((account_id, month), amount), totals|
          totals[account_id][month.to_date] = amount.to_d
        end
      end
    end
end
