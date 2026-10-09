module CategorySummariesHelper
  # Query params that keep the selected period when moving between screens.
  def category_summary_period_params(period)
    if period.key.present?
      { period: period.key }
    else
      { start_date: period.start_date, end_date: period.end_date }
    end
  end

  # The transactions of one category (with its subcategories) in the period.
  def category_summary_transactions_path(category, period)
    transactions_path(q: { categories: [ category.filter_value ], start_date: period.start_date, end_date: period.end_date })
  end

  # Where a root row leads: the subcategory breakdown when there is one,
  # otherwise straight to its transactions.
  def category_summary_root_path(row, period)
    if row.category.persisted? && row.category.parent?
      category_summary_path(row.category, category_summary_period_params(period))
    else
      category_summary_transactions_path(row.category, period)
    end
  end

  def category_summary_value(row)
    if row.transfers?
      t("category_summaries.transactions_count", count: row.count)
    else
      format_money(Money.new(row.total, Current.family.currency))
    end
  end
end
