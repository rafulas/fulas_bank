# Each movement can be marked as fixed (rent, insurance...), recurring (a
# fixed one that ends: a loan, a twelve-month plan) or variable (food, going
# out...). Empty means "work it out": fixed when the movement belongs to a
# recurring series, variable otherwise. The forecast estimates the monthly
# variable spending only from the variable ones, since the fixed and recurring
# ones are already projected one by one.
class AddExpenseTypeToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :expense_type, :string
    add_check_constraint :transactions,
                         "expense_type IS NULL OR expense_type IN ('variable', 'fixed', 'recurring')",
                         name: "chk_transactions_expense_type"
  end
end
