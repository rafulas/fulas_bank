# Fulas Bank: what the budget suggests for each category in a month, the
# same "media acotada" as the forecast's "Gastos varios" (see
# TrimmedMonthlyAverage): the same month in the last three finished years and
# the last six months, without the highest and the lowest.
#
# Spending of a category is what was spent minus what came back (refunds),
# never below zero. A subcategory has its own figure and also counts in its
# main category. Left out, as in the budget itself:
#   - one-off purchases (marked "Transacción puntual"), so a new TV does not
#     raise every month's budget; they still show in the reports;
#   - transfers, the Excluded and Transfers categories and movements excluded
#     by hand;
#   - accounts left out of reports.
#
# A month only counts once there is history for it (from the first imported
# movement on), so the suggestion grows as older statements are imported.
class MonthBudget::Estimate
  attr_reader :family, :user, :month, :today

  def initialize(family, user:, month:, today: Date.current)
    @family = family
    @user = user
    @month = month.beginning_of_month
    @today = today
  end

  # @return [Hash{String => BigDecimal}] category id => suggested amount, for
  #   every main category and subcategory with spending in the samples
  def amounts
    @amounts ||= category_ids.index_with do |category_id|
      TrimmedMonthlyAverage.mean(samples.map { |sample| totals.dig(sample, category_id) || 0 })
    end.select { |_, amount| amount.positive? }
  end

  # The months the suggestion averages (those with history).
  def samples
    @samples ||= begin
      start = history_start
      start ? TrimmedMonthlyAverage.sample_months(month, today: today).select { |sample| sample >= start.beginning_of_month } : []
    end
  end

  private
    def account_ids
      @account_ids ||= family.accounts.accessible_by(user).included_in_reports.pluck(:id)
    end

    def history_start
      family.entries.where(account_id: account_ids, entryable_type: "Transaction").minimum(:date)
    end

    def category_ids
      totals.values.flat_map(&:keys).uniq
    end

    # { month => { category_id => spending } }, a subcategory's spending
    # counted both for itself and for its main category.
    def totals
      @totals ||= begin
        rows = scope.group(Arel.sql("date_trunc('month', entries.date)"), "c.id", "c.parent_id")
                    .sum(Arel.sql("entries.amount * COALESCE(rates.rate, 1)"))

        rows.each_with_object(Hash.new { |hash, key| hash[key] = Hash.new(0) }) do |((date, id, parent_id), amount), result|
          sample = date.to_date
          result[sample][id] += amount.to_d
          result[sample][parent_id] += amount.to_d if parent_id
        end.transform_values { |by_category| by_category.transform_values { |amount| [ amount, 0 ].max } }
      end
    end

    def scope
      family.entries
            .excluding_split_parents
            .where(account_id: account_ids, entryable_type: "Transaction", excluded: false, date: (samples.min || month)..)
            .where(date: ...today.beginning_of_month)
            .joins("INNER JOIN transactions t ON t.id = entries.entryable_id")
            .joins("INNER JOIN categories c ON c.id = t.category_id")
            .joins(ActiveRecord::Base.sanitize_sql_array([
              "LEFT JOIN exchange_rates rates ON (rates.date = entries.date AND rates.from_currency = entries.currency AND rates.to_currency = ?)",
              family.currency
            ]))
            .where("t.kind NOT IN (?)", Transaction::TRANSFER_KINDS + [ "one_time" ])
            .where("c.id NOT IN (#{Category::ANALYTICS_NEUTRAL_IDS_SQL})")
    end
end
