# Fulas Bank: how much of each month's spending was fixed and how much
# variable, for the Resumen.
#
# A movement's type is the one chosen in its detail, or worked out by the app
# (see Transaction::ExpenseClassifiable): fixed when it pays a recurring
# series, variable otherwise. "Recurring" (a fixed one that ends, like a loan)
# is shown on its own.
#
# Only spending counts (refunds and income are left out), with the same
# scope as the rest of the Resumen: the accounts included in reports, no
# transfers, Excluded or Transfers categories.
class Category::FixedVariable
  MONTHS = 12
  TYPES = %w[fixed recurring variable].freeze

  Month = Data.define(:month, :fixed, :recurring, :variable) do
    def total
      fixed + recurring + variable
    end

    # Share of the month's spending that was fixed or recurring (committed).
    def committed_share
      total.positive? ? ((fixed + recurring) / total * 100).round : 0
    end
  end

  attr_reader :family, :account_ids, :today

  def initialize(family, account_ids:, today: Date.current)
    @family = family
    @account_ids = account_ids
    @today = today
  end

  def currency
    family.currency
  end

  # The last MONTHS months, oldest first, this one included.
  def months
    @months ||= begin
      first = today.beginning_of_month << (MONTHS - 1)
      (0...MONTHS).map do |offset|
        month = first >> offset
        values = totals.fetch(month, {})
        Month.new(month: month, fixed: values.fetch("fixed", 0.to_d), recurring: values.fetch("recurring", 0.to_d),
                  variable: values.fetch("variable", 0.to_d))
      end
    end
  end

  def max_total
    months.map(&:total).max.to_d
  end

  # The committed share of the whole period.
  def committed_share
    total = months.sum(&:total)
    total.positive? ? (months.sum { |month| month.fixed + month.recurring } / total * 100).round : 0
  end

  def any?
    months.any? { |month| month.total.positive? }
  end

  private
    # { month => { type => spending } }
    def totals
      @totals ||= begin
        type_sql = <<~SQL.squish
          CASE
            WHEN t.expense_type IN ('fixed', 'recurring') THEN t.expense_type
            WHEN t.expense_type IS NULL AND entries.id IN (SELECT entry_id FROM recurring_allocations WHERE entry_id IS NOT NULL) THEN 'fixed'
            ELSE 'variable'
          END
        SQL

        rows = family.entries
                     .excluding_split_parents
                     .where(account_id: account_ids, entryable_type: "Transaction", excluded: false,
                            date: (today.beginning_of_month << (MONTHS - 1))..today)
                     .where("entries.amount > 0")
                     .joins("INNER JOIN transactions t ON t.id = entries.entryable_id")
                     .joins(ActiveRecord::Base.sanitize_sql_array([
                       "LEFT JOIN exchange_rates rates ON (rates.date = entries.date AND rates.from_currency = entries.currency AND rates.to_currency = ?)",
                       currency
                     ]))
                     .where(Transaction.counts_by_kind_sql("t"))
                     .where("t.category_id IS NULL OR t.category_id NOT IN (#{Category::ANALYTICS_NEUTRAL_IDS_SQL})")
                     .group(Arel.sql("date_trunc('month', entries.date)"), Arel.sql(type_sql))
                     .sum(Arel.sql("entries.amount * COALESCE(rates.rate, 1)"))

        rows.each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |((month, type), amount), result|
          result[month.to_date][type] = amount.to_d
        end
      end
    end
end
