# Totals of a property's expenses for its "Expenses" tab: everything spent,
# this year's, and how much went to each kind (mortgage, renovations...).
# Expenses the app proposed and the user has not confirmed are left out.
class Property::ExpenseSummary
  attr_reader :property, :as_of

  def initialize(property, as_of: Date.current)
    @property = property
    @as_of = as_of
  end

  def expenses
    @expenses ||= property.expenses.settled.includes(entry: :account).with_attached_attachments.reverse_chronological.to_a
  end

  def empty?
    expenses.empty?
  end

  def currency
    property.account.currency
  end

  def total
    money(expenses.sum { |expense| expense.amount.to_d })
  end

  def total_this_year
    money(expenses.select { |expense| expense.date.year == as_of.year }.sum { |expense| expense.amount.to_d })
  end

  # [ kind, Money ] for the kinds with any expense, largest first.
  def by_kind
    expenses.group_by(&:kind)
            .map { |kind, list| [ kind, money(list.sum { |expense| expense.amount.to_d }) ] }
            .sort_by { |_, amount| -amount.amount }
  end

  private
    def money(amount)
      Money.new(amount, currency)
    end
end
