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

  # Fulas Bank: a month a category spent at least this many times its usual
  # (the median of its months with spending), and at least OUTLIER_MIN, is
  # pointed out: usually a one-off payment to mark as such.
  OUTLIER_FACTOR = 3
  OUTLIER_MIN = 100

  attr_reader :family, :accounts, :month, :today, :plan

  def initialize(family, accounts:, month:, today: Date.current, plan: nil)
    @family = family
    @accounts = accounts
    @month = month.beginning_of_month
    @today = today
    @plan = plan
  end

  def estimate
    @estimate ||= Forecast::VariableEstimate.new(family, accounts: accounts, today: today, plan: plan,
                                                 budget_source: Forecast::BudgetSource.for_plan(plan, today: today))
  end

  # The result: what the forecast expects to spend in the month.
  def monthly
    estimate.combined_monthly(month)
  end

  # The sample months, newest first, each flagged when it is one of the two
  # left out (there must be at least three, as in TrimmedMonthlyAverage).
  # Their totals leave out the categories planned for the month.
  def samples
    @samples ||= begin
      months = estimate.combined_sample_months(month)
      planned = estimate.planned_ids(month) | estimate.budget_covered_ids(month)
      totals = months.index_with { |sample| estimate.combined_total(sample, without: planned) }
      dropped = dropped_months(totals)

      months.map { |sample| Sample.new(month: sample, total: totals[sample], dropped: dropped.include?(sample)) }
    end
  end

  def sample_months
    samples.map(&:month)
  end

  # Fulas Bank: the month's plans (Forecast::VariablePlan), added to the
  # average of the samples.
  def plans
    plan ? plan.plans_for(month) : []
  end

  # The month's plans with their categories: [[plan, category]].
  def plans_with_categories
    by_id = family.categories.where(id: plans.map(&:category_id)).index_by { |category| category.id.to_s }
    plans.filter_map { |plan| [ plan, by_id[plan.category_id] ] if by_id[plan.category_id] }
  end

  # The plan for a category this month, its own or its parent's.
  def plan_covering(category)
    return unless category

    plan_for(category.id) || (category.parent_id && plan_for(category.parent_id))
  end

  def plan_for(category_id)
    plan&.plan_for(month, category_id)
  end

  # Fulas Bank: the budgets that rule this month: [[budget, amount,
  # recurring, variable part]], the largest first.
  def budget_rows
    source = estimate.budget_source
    return [] unless source

    @budget_rows ||= source.variable_parts(month).filter_map do |id, part|
      group = source.find_group(id)
      [ group, source.budgets(month)[id], source.recurring_of(group, month), part ] if group
    end.sort_by { |row| -row[1] }
  end

  # The budget row a category counts in, when its budget rules this month.
  def budget_row_for(category)
    source = estimate.budget_source
    group = source&.group_for(category)
    group && budget_rows.find { |row| row.first == group }
  end

  # Fulas Bank: the categories (as strings, subcategories included) whose
  # budget or plan rules the month: they are not in the sample months'
  # totals, which only average the rest.
  def outside_average_ids
    @outside_average_ids ||= (estimate.planned_ids(month) | estimate.budget_covered_ids(month)).map(&:to_s)
  end

  # Whether a category's spending is in the average (no budget or plan
  # rules it this month). Movements with no category always are.
  def in_average?(row)
    row.category.nil? || outside_average_ids.exclude?(row.category.id.to_s)
  end

  def budgeted?(row)
    row.category.present? && budget_row_for(row.category).present?
  end

  # No category with spending is averaged: budgets and plans make the whole
  # month, and the sample months would only show zeros.
  def all_planned?
    categories.any? && categories.none? { |row| in_average?(row) }
  end

  # A month far above what the category usually spends (see OUTLIER_FACTOR).
  def outlier?(row, sample)
    value = row.totals[sample]
    return false if value.nil? || value < OUTLIER_MIN

    spent = row.totals.values.select(&:positive?).sort
    return false if spent.size < 3

    value >= spent[spent.size / 2] * OUTLIER_FACTOR
  end

  def any_outlier?
    categories.any? { |row| sample_months.any? { |sample| outlier?(row, sample) } }
  end

  # The categories left out of the forecast, by name.
  def excluded_categories
    return [] unless plan

    family.categories.where(id: plan.excluded_ids).includes(:parent).alphabetically
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
                                                          from: sample_months.min, to: sample_months.max.end_of_month,
                                                          excluded_category_ids: plan&.excluded_with_children || [])
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
