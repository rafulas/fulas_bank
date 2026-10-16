# Fulas Bank: the family's insurance policies (car, motorbike, home, life...),
# each optionally tied to the asset it covers (a vehicle or property account).
class CreateInsurances < ActiveRecord::Migration[8.1]
  def change
    create_table :insurances, id: :uuid do |t|
      t.references :family, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      # The insured asset. Deleting the asset keeps the policy, unlinked.
      t.references :account, foreign_key: { on_delete: :nullify }, type: :uuid
      t.string :name, null: false
      t.string :kind, null: false, default: "other"
      t.string :insurer
      t.string :policy_number
      t.string :coverage
      t.string :assistance_phone
      t.decimal :premium, precision: 19, scale: 4
      t.string :currency, null: false
      t.string :payment_frequency, null: false, default: "annual"
      t.date :start_date
      t.date :renewal_date
      t.boolean :active, null: false, default: true
      t.text :notes
      t.timestamps
    end

    add_check_constraint :insurances, "premium IS NULL OR premium >= 0", name: "chk_insurances_premium_not_negative"
  end
end
