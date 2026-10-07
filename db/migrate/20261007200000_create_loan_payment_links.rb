class CreateLoanPaymentLinks < ActiveRecord::Migration[8.1]
  def change
    # A bank movement recorded as the payment of a loan instalment. The
    # movement stays in the account it was paid from; the link is what makes
    # it show on the loan.
    create_table :loan_payment_links, id: :uuid do |t|
      t.references :loan, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :entry, null: false, type: :uuid, foreign_key: { on_delete: :cascade },
        index: { unique: true }

      t.timestamps
    end
  end
end
