# Fulas Bank: partial early repayments of a loan (Loan#prepayment_rows).
class AddPrepaymentsToLoans < ActiveRecord::Migration[8.1]
  def change
    add_column :loans, :prepayments, :jsonb, default: [], null: false
  end
end
