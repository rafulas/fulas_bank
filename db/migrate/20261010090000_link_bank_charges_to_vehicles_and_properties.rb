# Bank charges can now be linked to a vehicle or a property automatically:
#
# - `vehicle_logs.suggestion` and `property_expenses.suggestion` mark a link
#   the app proposed and the user has not confirmed yet: "link" when an
#   existing record was matched with a charge, "new" when the record itself
#   was created from the charge.
# - `property_expenses` is the property's own list of costs (renovations,
#   insurance, mortgage...), each one tied to the bank charge that paid it.
# - `asset_link_rejections` remembers the charges the user turned down for an
#   account, so they are not proposed again.
class LinkBankChargesToVehiclesAndProperties < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicle_logs, :suggestion, :string
    add_check_constraint :vehicle_logs, "suggestion IS NULL OR suggestion IN ('link', 'new')", name: "chk_vehicle_logs_suggestion"

    create_table :property_expenses, id: :uuid do |t|
      t.references :property, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.date :date, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false, default: 0
      t.string :currency, null: false
      t.references :entry, type: :uuid, index: { unique: true }, foreign_key: { on_delete: :nullify }
      t.text :notes
      t.string :suggestion

      t.timestamps
    end

    add_index :property_expenses, [ :property_id, :date ]
    add_check_constraint :property_expenses, "amount >= 0", name: "chk_property_expenses_amount_non_negative"
    add_check_constraint :property_expenses, "suggestion IS NULL OR suggestion IN ('link', 'new')", name: "chk_property_expenses_suggestion"

    create_table :asset_link_rejections, id: :uuid do |t|
      t.references :entry, null: false, type: :uuid, index: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, type: :uuid, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :asset_link_rejections, [ :entry_id, :account_id ], unique: true
  end
end
