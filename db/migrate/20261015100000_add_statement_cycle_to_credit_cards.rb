# Fulas Bank: a credit card's monthly statement (when it closes, when it is
# charged and from which account), the movements that go to the next
# statement, and the purchases paid in instalments.
class AddStatementCycleToCreditCards < ActiveRecord::Migration[8.1]
  def change
    add_column :credit_cards, :statement_closing_day, :integer
    add_column :credit_cards, :payment_day, :integer
    add_column :credit_cards, :consolidation_days, :integer, null: false, default: 0
    add_reference :credit_cards, :payment_account, type: :uuid, foreign_key: { to_table: :accounts, on_delete: :nullify }
    add_check_constraint :credit_cards, "statement_closing_day BETWEEN 1 AND 31", name: "chk_credit_cards_closing_day"
    add_check_constraint :credit_cards, "payment_day BETWEEN 1 AND 31", name: "chk_credit_cards_payment_day"
    add_check_constraint :credit_cards, "consolidation_days BETWEEN 0 AND 10", name: "chk_credit_cards_consolidation_days"

    add_column :transactions, :next_card_statement, :boolean, null: false, default: false

    create_table :card_financings, id: :uuid do |t|
      t.references :family, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :entry, foreign_key: { on_delete: :nullify }, type: :uuid, index: { unique: true }
      t.string :name, null: false
      t.date :purchase_date, null: false
      t.decimal :financed_amount, precision: 19, scale: 4, null: false
      t.integer :installments_count, null: false
      t.decimal :installment_amount, precision: 19, scale: 4, null: false
      t.decimal :fee_amount, precision: 19, scale: 4, null: false, default: 0
      t.string :currency, null: false
      t.timestamps
    end
    add_check_constraint :card_financings, "financed_amount > 0", name: "chk_card_financings_amount_positive"
    add_check_constraint :card_financings, "installments_count BETWEEN 1 AND 120", name: "chk_card_financings_installments"
    add_check_constraint :card_financings, "installment_amount > 0", name: "chk_card_financings_installment_positive"
    add_check_constraint :card_financings, "fee_amount >= 0", name: "chk_card_financings_fee_not_negative"
  end
end
