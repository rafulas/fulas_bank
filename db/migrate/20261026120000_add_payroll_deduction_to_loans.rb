# Fulas Bank: a loan whose instalment the employer takes out of the pay
# (Loan::PayrollDeduction): the movements are booked in the loan itself.
class AddPayrollDeductionToLoans < ActiveRecord::Migration[8.1]
  def change
    add_column :loans, :payroll_deducted, :boolean, default: false, null: false
    add_column :loans, :payroll_deducted_since, :date
    add_reference :loans, :payroll_expense_category, type: :uuid, foreign_key: { to_table: :categories, on_delete: :nullify }, index: true
    add_reference :loans, :payroll_income_category, type: :uuid, foreign_key: { to_table: :categories, on_delete: :nullify }, index: true
  end
end
