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
# in the Excluded or Transfers categories, nor money put into investments
# (the «Inversiones» categories). Only spending counts: income and
# refunds are left out, so the estimate errs on the side of caution.
class Forecast::VariableEstimate
  SAME_MONTH_YEARS = TrimmedMonthlyAverage::SAME_MONTH_YEARS
  RECENT_MONTHS = TrimmedMonthlyAverage::RECENT_MONTHS
  INVESTMENT_ROOT_NAME = "Inversiones".freeze

  # The movements that count as variable spending in `accounts` between
  # two dates, joined to their transactions. Forecast::VariableBreakdown
  # lists them, so both always agree.
  def self.spending_entries(family, accounts:, from:, to:, excluded_category_ids: [])
    scope = without_investments(base_spending_entries(family, accounts: accounts, from: from, to: to), family)
    return scope if excluded_category_ids.blank?

    # Fulas Bank: the categories left out in «Ver cálculo» (Forecast::VariablePlan).
    scope.where("transactions.category_id IS NULL OR transactions.category_id NOT IN (?)", excluded_category_ids)
  end

  def self.base_spending_entries(family, accounts:, from:, to:)
    family.entries
          .excluding_split_parents
          .where(account_id: accounts.map(&:id), entryable_type: "Transaction", excluded: false, date: from..to)
          .where("entries.amount > 0")
          .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
          .where.not(transactions: { kind: Transaction::TRANSFER_KINDS + [ "one_time" ] })
          .where("transactions.category_id IS NULL OR transactions.category_id NOT IN (#{Category::ANALYTICS_NEUTRAL_IDS_SQL})")
          .where.not(transactions: { id: Transfer.select(:inflow_transaction_id) })
          .where.not(transactions: { id: Transfer.select(:outflow_transaction_id) })
          .where(Transaction.variable_expense_sql)
  end

  # Fulas Bank: money put into investments, pension plans or savings (the
  # «Inversiones» branch, and Sure's investment contributions category) is
  # not spending, even when it leaves as an ordinary charge.
  # Uncategorized movements stay: a bare NOT IN would drop them too.
  def self.without_investments(scope, family)
    ids = investment_category_ids(family)
    return scope if ids.empty?

    scope.where("transactions.category_id IS NULL OR transactions.category_id NOT IN (?)", ids)
  end

  def self.investment_category_ids(family)
    names = [ Category::FulasTree::INVESTMENT_CONTRIBUTIONS_NAME, *Category.all_investment_contributions_names ]
    roots = family.categories.where(parent_id: nil, name: INVESTMENT_ROOT_NAME).select(:id)

    family.categories.where(name: names).or(family.categories.where(id: roots))
          .or(family.categories.where(parent_id: roots)).pluck(:id)
  end

  attr_reader :family, :accounts, :today, :plan

  # `plan` (Forecast::VariablePlan): the categories left out, and those
  # planned for a month.
  def initialize(family, accounts:, today: Date.current, plan: nil)
    @family = family
    @accounts = accounts
    @today = today
    @plan = plan
  end

  # Expected spending (positive) of `account` in the whole of `month` (any day
  # of it), in the account's currency. Zero without history.
  def monthly(account, month)
    values = sample_months(month.beginning_of_month).filter_map do |sample|
      account_total(account, sample) if covered?(account, sample)
    end
    TrimmedMonthlyAverage.mean(values)
  end

  # What `account` has already spent on variable things in `month`, to know
  # how much of this month's estimate is still to come.
  def spent(account, month)
    account_total(account, month.beginning_of_month)
  end

  # The same estimate for all the accounts together, as one figure: what is
  # spent across them each month, averaged the same way. A month counts once
  # any of them has history. The categories planned for the month are left
  # out of the average and their planned amounts added instead.
  def combined_monthly(month)
    month = month.beginning_of_month
    planned = planned_ids(month)
    values = combined_sample_months(month).map { |sample| combined_total(sample, without: planned) }
    TrimmedMonthlyAverage.mean(values) + planned_total(month)
  end

  # What has already been spent in `month`, counted the way the estimate
  # is: a planned category counts up to its planned amount.
  def combined_spent(month)
    month = month.beginning_of_month
    planned = planned_ids(month)
    return combined_total(month) if planned.empty?

    in_planned = combined_total(month) - combined_total(month, without: planned)
    combined_total(month, without: planned) + [ in_planned, planned_total(month) ].min
  end

  # The months that go into the combined estimate for `month`, newest first:
  # the sample months from the first one any account has history in.
  def combined_sample_months(month)
    start = history_starts.values.compact.min
    return [] unless start

    # A month with no variable spending at all in any account is a month
    # with no data (an account's single old movement makes it look covered),
    # not a month in which nothing was spent: it is left out of the average.
    sample_months(month.beginning_of_month).select do |sample|
      sample >= start.beginning_of_month && combined_total(sample).positive?
    end
  end

  # What all the accounts together spent on variable things in `month`, in
  # the family's currency (an account in another currency is converted at
  # today's rate, or added as is when there is no rate).
  #
  # `without`: category ids whose spending is left out.
  def combined_total(month, without: [])
    monthly_totals.sum do |account_id, months|
      in_family_currency(sum_categories(months[month.beginning_of_month], without), accounts_by_id[account_id])
    end.to_d
  end

  def planned_ids(month)
    plan ? plan.planned_ids(month) : []
  end

  def planned_total(month)
    plan ? plan.planned_total(month) : 0.to_d
  end

  # The months averaged for `month`, newest first.
  def sample_months(month)
    TrimmedMonthlyAverage.sample_months(month, today: today)
  end

  private
    def accounts_by_id
      @accounts_by_id ||= accounts.index_by(&:id)
    end

    def in_family_currency(amount, account)
      return amount if amount.zero? || account.nil? || account.currency == family.currency

      Money.new(amount, account.currency).exchange_to(family.currency).amount
    rescue Money::ConversionError
      amount
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

    def account_total(account, month)
      sum_categories(monthly_totals.dig(account.id, month), [])
    end

    # A month's spending in one account, without the categories in `without`.
    def sum_categories(by_category, without)
      return 0.to_d if by_category.blank?

      by_category.sum { |category_id, amount| without.include?(category_id.to_s) ? 0 : amount }.to_d
    end

    # { account_id => { month => { category_id => variable spending } } }
    # since the oldest month any sample can reach: the same month three
    # finished years back. The categories left out of the forecast are not
    # in it.
    def monthly_totals
      @monthly_totals ||= begin
        from = current_month << (12 * SAME_MONTH_YEARS)

        rows = self.class.spending_entries(family, accounts: accounts, from: from, to: today.end_of_month,
                                           excluded_category_ids: plan&.excluded_with_children || [])
                   .group(:account_id, Arel.sql("date_trunc('month', entries.date)"), "transactions.category_id")
                   .sum(:amount)

        rows.each_with_object(Hash.new { |hash, key| hash[key] = Hash.new { |inner, month| inner[month] = {} } }) do |((account_id, month, category_id), amount), totals|
          totals[account_id][month.to_date][category_id.to_s] = amount.to_d
        end
      end
    end
end
