# Fulas Bank: whether a movement is fixed (rent, insurance, salary), recurring
# (a fixed one that ends: a loan, a twelve-month plan) or variable (food,
# going out...).
#
# Nothing is chosen by default (`expense_type` empty), and then it works itself
# out: fixed when the movement belongs to a recurring series, variable
# otherwise. Choosing one is what Transaction::ExpenseTypeChange does.
#
# The forecast uses it to estimate the monthly variable spending only from the
# variable movements: the fixed and recurring ones are already projected one
# by one from their series, and counting them again would spend them twice.
module Transaction::ExpenseClassifiable
  extend ActiveSupport::Concern

  EXPENSE_TYPES = %w[variable fixed recurring].freeze

  included do
    validates :expense_type, inclusion: { in: EXPENSE_TYPES }, allow_nil: true
  end

  class_methods do
    # Transactions whose type is variable, chosen or worked out, as SQL for an
    # entries query joined to transactions. "Worked out" means not paid by any
    # recurring series.
    def variable_expense_sql
      <<~SQL.squish
        (transactions.expense_type = 'variable'
          OR (transactions.expense_type IS NULL
            AND entries.id NOT IN (SELECT entry_id FROM recurring_allocations WHERE entry_id IS NOT NULL)))
      SQL
    end
  end

  def effective_expense_type
    expense_type.presence || (recurring_series.present? ? "fixed" : "variable")
  end

  def expense_type_chosen?
    expense_type.present?
  end

  # The recurring series this movement pays (the one the app matched it to),
  # or the one created from it with "Mark as recurring".
  def recurring_series
    return @recurring_series if defined?(@recurring_series)

    @recurring_series = matched_recurring_series || existing_manual_recurring_transaction
  end

  private
    def matched_recurring_series
      return nil unless entry&.persisted?

      RecurringTransaction.joins(recurring_occurrences: :allocations)
                          .where(recurring_allocations: { entry_id: entry.id })
                          .order("recurring_allocations.created_at DESC")
                          .first
    end
end
