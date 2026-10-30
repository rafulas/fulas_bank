# Fulas Bank: what the recurring payments are expected to take in a month,
# by main category (a subcategory counts in its main one). Bills,
# subscriptions and loan instalments with a category; not income, and not
# transfers between the family's accounts. Every payment of the month counts,
# so an annual insurance falls in its own month.
#
# Used to turn a budget into its variable part in the forecast (budget −
# the recurring payments of its categories, Forecast::BudgetSource) and, the
# other way round, to build a month's budget (variable estimate + recurring,
# Forecast::BudgetPlanner).
class Forecast::CategoryRecurring
  attr_reader :family

  def initialize(family)
    @family = family
    @months = {}
  end

  # @return [Hash{String => BigDecimal}] main category id => amount
  def for(month)
    by_category(month).each_with_object(Hash.new(0.to_d)) do |(id, amount), totals|
      totals[main_ids.fetch(id, id)] += amount
    end
  end

  # What the payments of `month` take in the categories `ids` (a budget's,
  # BudgetGroup#expanded_category_ids).
  def total(month, ids)
    ids = ids.map(&:to_s)
    by_category(month).sum { |id, amount| ids.include?(id) ? amount : 0 }.to_d
  end

  # @return [Hash{String => BigDecimal}] category id (as given to the
  #   series, subcategory or main) => amount
  def by_category(month)
    month = month.beginning_of_month
    @months[month] ||= series.each_with_object(Hash.new(0.to_d)) do |item, totals|
      payments = item.schedule.occurrences_between(month, month.end_of_month).size
      next if payments.zero?

      totals[item.category_id.to_s] += amount_of(item) * payments
    end
  end

  private
    def main_ids
      @main_ids ||= series.to_h { |item| [ item.category_id.to_s, (item.category.parent_id || item.category_id).to_s ] }
    end

    def series
      @series ||= family.recurring_transactions.active
                        .where.not(category_id: nil)
                        .where(destination_account_id: nil)
                        .where("recurring_transactions.amount > 0")
                        .includes(:category, :recurrence_rules)
                        .to_a
    end

    def amount_of(item)
      amount = item.amount_average? && item.expected_amount_avg.present? ? item.expected_amount_avg : item.amount
      amount.to_d.abs
    end
end
