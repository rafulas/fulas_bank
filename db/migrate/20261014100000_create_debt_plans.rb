class CreateDebtPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :debt_plans, id: :uuid do |t|
      t.references :family, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: { unique: true }
      t.references :account, foreign_key: { on_delete: :nullify }, type: :uuid
      t.string :strategy, null: false, default: "avalanche"
      t.decimal :monthly_extra, precision: 19, scale: 4, null: false, default: 0
      t.boolean :feeds_forecast, null: false, default: false
      t.jsonb :loan_settings, null: false, default: {}
      t.timestamps
    end

    create_table :debt_plan_extra_payments, id: :uuid do |t|
      t.references :debt_plan, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.date :date, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :name
      t.date :repeats_until
      t.timestamps
    end
    add_check_constraint :debt_plan_extra_payments, "amount > 0", name: "chk_debt_plan_extra_payments_amount_positive"
  end
end
