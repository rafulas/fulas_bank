class AddLoanAccountToRecurringTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :recurring_transactions, :loan_account, type: :uuid, foreign_key: { to_table: :accounts, on_delete: :nullify }, index: true
  end
end
