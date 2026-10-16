# Fulas Bank: three improvements that tie bank movements to what they pay
# for, and recognise a statement's account.
#
# 1. trades.bank_entry_suggested: the bank movement of a buy or sale was
#    proposed by the app (TradeLinker) and waits for the user to confirm it.
# 2. insurance_payments: each instalment of an insurance paid in custom
#    instalments, on a given day, with the bank charge that paid it (or
#    marked paid by hand). The app proposes the charge; the user confirms or
#    turns it down (rejected_entry_ids, so it is not proposed again).
# 3. accounts.statement_reference and imports.statement_reference: the end of
#    the IBAN printed on a bank statement, so the next statement of the same
#    account is recognised on its own.
class AddLinksAndStatementReferences < ActiveRecord::Migration[8.1]
  def change
    add_column :trades, :bank_entry_suggested, :boolean, default: false, null: false

    create_table :insurance_payments, id: :uuid do |t|
      t.references :insurance, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.date :due_on, null: false
      t.references :entry, foreign_key: { on_delete: :nullify }, type: :uuid, index: { unique: true }
      t.boolean :suggested, null: false, default: false
      t.boolean :paid_manually, null: false, default: false
      t.jsonb :rejected_entry_ids, null: false, default: []
      t.timestamps
    end
    add_index :insurance_payments, %i[insurance_id due_on], unique: true

    add_column :accounts, :statement_reference, :string
    add_column :imports, :statement_reference, :string
  end
end
