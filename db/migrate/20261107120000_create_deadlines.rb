# Fulas Bank: Vencimientos y garantías — dated things to renew or keep an
# eye on (ITV, warranties, documents, taxes, check-ups), with a reminder.
class CreateDeadlines < ActiveRecord::Migration[8.1]
  def change
    create_table :deadlines, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, foreign_key: { on_delete: :nullify }, type: :uuid
      t.string :name, null: false
      t.string :kind, null: false, default: "other"
      t.date :due_on, null: false
      t.integer :remind_days, null: false, default: 30
      t.integer :repeat_months
      t.decimal :amount, precision: 19, scale: 4
      t.string :currency
      t.text :notes
      t.date :completed_on

      t.timestamps
    end

    add_index :deadlines, %i[family_id due_on]
    add_check_constraint :deadlines, "remind_days >= 0", name: "chk_deadlines_remind_days_not_negative"
    add_check_constraint :deadlines, "repeat_months IS NULL OR repeat_months > 0", name: "chk_deadlines_repeat_months_positive"
  end
end
