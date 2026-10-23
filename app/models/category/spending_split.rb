# Fulas Bank: the 50/30/20 split of a period, with real figures. What came
# in, and how much of it went on necessary things ("Necesario"), on things
# that could be done without ("Prescindible") and what was left
# ("Ahorro"), against the target the user picked (50/30/20 by default).
#
# - Each category's class is its own or its main category's
#   (Category::SpendingClass), so "Restaurantes" can be discretionary inside
#   "Comida y bebida".
# - A main category whose movements add up to money in (salary, refunds
#   bigger than spending) is income; the rest is spending, by class.
# - Saving is what is left: income minus necessary and discretionary
#   spending (and spending not classified yet). Money moved to investments in
#   a "savings" category is part of it, not taken from it.
# - What counts is the same as in the Resumen (Category::Analysis): the
#   accounts included in reports, no transfers, Excluded or Transfers.
class Category::SpendingSplit
  PRESETS = {
    "50-30-20" => [ 50, 30, 20 ],
    "60-25-15" => [ 60, 25, 15 ],
    "40-30-30" => [ 40, 30, 30 ]
  }.freeze
  DEFAULT_TARGET = PRESETS.fetch("50-30-20")
  TARGET_PREFERENCE = "spending_split_target".freeze

  Part = Data.define(:key, :amount, :share, :target)

  attr_reader :family, :range, :account_ids, :target

  # @param target [Array<Integer>] necessary, discretionary and saving
  #   percentages, adding up to 100
  def initialize(family, range:, account_ids:, target: DEFAULT_TARGET)
    @family = family
    @range = range
    @account_ids = account_ids
    @target = valid_target?(target) ? target.map(&:to_i) : DEFAULT_TARGET
  end

  def self.target_for(user)
    saved = Array(user&.preferences&.dig(TARGET_PREFERENCE)).map(&:to_i)
    saved.size == 3 && saved.sum == 100 && saved.all? { |value| value >= 0 } ? saved : DEFAULT_TARGET
  end

  def currency
    family.currency
  end

  def income
    money(totals[:income])
  end

  def unclassified
    money(totals[:unclassified])
  end

  # Necessary, discretionary and saving, with their share of the income.
  def parts
    essential = totals[:essential]
    discretionary = totals[:discretionary] + totals[:unclassified]
    savings = totals[:income] - essential - discretionary

    [
      part(:essential, essential, target[0]),
      part(:discretionary, discretionary, target[1]),
      part(:savings, savings, target[2])
    ]
  end

  def any?
    totals[:income].positive?
  end

  private
    def valid_target?(values)
      values = Array(values).map(&:to_i)
      values.size == 3 && values.sum == 100 && values.all? { |value| value >= 0 }
    end

    def part(key, amount, target_share)
      share = totals[:income].positive? ? (amount / totals[:income] * 100).round : 0
      Part.new(key: key, amount: money(amount), share: share, target: target_share)
    end

    def money(amount)
      Money.new(amount, currency)
    end

    # { income:, essential:, discretionary:, savings:, unclassified: }
    def totals
      @totals ||= begin
        result = Hash.new(0.to_d)
        rows_by_root.each_value do |rows|
          # Income is added up apart from spending (Transaction.income_flow_sql),
          # so a salary with no category does not cancel the purchases with
          # no category.
          incoming, spending = rows.partition { |row| row[:income] }
          result[:income] -= incoming.sum { |row| row[:amount] }

          net = spending.sum { |row| row[:amount] }
          if net.negative?
            # Refunds bigger than the spending: money in.
            result[:income] -= net
          else
            # "income" is not a spending class: an income category that
            # spends counts as unclassified.
            spending.each { |row| result[row[:class].in?(%i[essential discretionary savings]) ? row[:class] : :unclassified] += row[:amount] }
          end
        end
        result
      end
    end

    # { root id => [ { amount:, class:, income: } per category and side ] },
    # spending positive.
    def rows_by_root
      sums = family.entries
                   .excluding_split_parents
                   .where(account_id: account_ids, entryable_type: "Transaction", excluded: false, date: range)
                   .joins("INNER JOIN transactions t ON t.id = entries.entryable_id")
                   .joins("LEFT JOIN categories c ON c.id = t.category_id LEFT JOIN categories parent_c ON parent_c.id = c.parent_id")
                   .joins(ActiveRecord::Base.sanitize_sql_array([
                     "LEFT JOIN exchange_rates rates ON (rates.date = entries.date AND rates.from_currency = entries.currency AND rates.to_currency = ?)",
                     currency
                   ]))
                   .where("t.kind NOT IN (?) OR t.id IN (#{Transaction::INVESTMENT_WITHDRAWAL_IDS_SQL})", Transaction::ANALYTICS_EXCLUDED_KINDS)
                   .where("t.category_id IS NULL OR t.category_id NOT IN (#{Category::ANALYTICS_NEUTRAL_IDS_SQL})")
                   .group(Arel.sql("COALESCE(parent_c.id, c.id)"), Arel.sql("COALESCE(c.spending_class, parent_c.spending_class)"))
                   .group(Arel.sql(Transaction.income_flow_sql(table: "t")))
                   .sum(Arel.sql("entries.amount * COALESCE(rates.rate, 1)"))

      sums.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |((root_id, spending_class, inflow), amount), grouped|
        grouped[root_id || "uncategorized"] << {
          amount: amount.to_d,
          class: spending_class&.to_sym,
          income: ActiveModel::Type::Boolean.new.cast(inflow)
        }
      end
    end
end
