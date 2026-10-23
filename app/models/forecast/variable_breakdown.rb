# Fulas Bank: how the forecast's "Gastos varios" line of a month is worked
# out («Ver cálculo»), so the user can check it.
#
# It shows the same numbers Forecast::VariableEstimate uses:
#   - the sample months (the same month of past years and the last six
#     months), with what was spent on variable things in each, and which two
#     are dropped (the highest and the lowest) before averaging;
#   - the categories that spending was in, month by month, the heaviest
#     first;
#   - for one category, the movements behind each month's figure.
class Forecast::VariableBreakdown
  # One sample month: its total and whether the trimmed mean drops it.
  Sample = Data.define(:month, :total, :dropped)

  # One category (nil for the uncategorized movements) with what it spent in
  # each sample month and its average over them.
  CategoryRow = Data.define(:category, :totals, :average) do
    def key
      category&.id || NONE
    end
  end

  # The key that stands for "no category" in a link.
  NONE = "none".freeze

  attr_reader :family, :accounts, :month, :today

  def initialize(family, accounts:, month:, today: Date.current)
    @family = family
    @accounts = accounts
    @month = month.beginning_of_month
    @today = today
  end

  def estimate
    @estimate ||= Forecast::VariableEstimate.new(family, accounts: accounts, today: today)
  end

  # The result: what the forecast expects to spend in the month.
  def monthly
    estimate.combined_monthly(month)
  end

  # The sample months, newest first, each flagged when it is one of the two
  # left out (there must be at least three, as in TrimmedMonthlyAverage).
  def samples
    @samples ||= begin
      months = estimate.combined_sample_months(month)
      totals = months.index_with { |sample| estimate.combined_total(sample) }
      dropped = dropped_months(totals)

      months.map { |sample| Sample.new(month: sample, total: totals[sample], dropped: dropped.include?(sample)) }
    end
  end

  def sample_months
    samples.map(&:month)
  end

  # The categories the sample months' spending was in, the heaviest first.
  def categories
    @categories ||= begin
      totals = Hash.new { |hash, key| hash[key] = {} }
      category_totals.each do |(category_id, sample), amount|
        totals[category_id][sample.to_date] = amount.to_d
      end

      by_id = family.categories.where(id: totals.keys.compact).includes(:parent).index_by(&:id)
      rows = totals.map do |category_id, months|
        values = sample_months.map { |sample| months[sample] || 0.to_d }
        average = values.empty? ? 0.to_d : (values.sum / values.size).round(2)
        CategoryRow.new(category: by_id[category_id], totals: months, average: average)
      end

      rows.sort_by { |row| -row.average }
    end
  end

  # A category's row, by its id or NONE.
  def category_row(key)
    categories.find { |row| row.key.to_s == key.to_s }
  end

  # The movements behind a category's figures, newest first, grouped by
  # sample month: { month => [entries] }.
  def entries_for(key)
    scope = sample_scope.preload(:account, entryable: :category).order(date: :desc)
    scope = key.to_s == NONE ? scope.where(transactions: { category_id: nil }) : scope.where(transactions: { category_id: key })

    scope.to_a.group_by { |entry| entry.date.beginning_of_month }
  end

  private
    # Whole sample months only: the movements dated in one of them.
    def sample_scope
      return Entry.none if sample_months.empty?

      scope = Forecast::VariableEstimate.spending_entries(family, accounts: accounts,
                                                          from: sample_months.min, to: sample_months.max.end_of_month)
      scope.where("date_trunc('month', entries.date) IN (?)", sample_months)
    end

    def category_totals
      sample_scope.group("transactions.category_id", Arel.sql("date_trunc('month', entries.date)")).sum(:amount)
    end

    # The months the trimmed mean leaves out: the lowest and the highest, once
    # there are at least three.
    def dropped_months(totals)
      return [] if totals.size < 3

      sorted = totals.sort_by { |sample, total| [ total, sample ] }
      [ sorted.first.first, sorted.last.first ]
    end
end
