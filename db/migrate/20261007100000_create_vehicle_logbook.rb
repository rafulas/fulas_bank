class CreateVehicleLogbook < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :fuel_type, :string
    add_column :vehicles, :license_plate, :string

    create_table :vehicle_maintenance_items, id: :uuid do |t|
      t.references :vehicle, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :interval_km
      t.integer :interval_months
      t.date :last_done_on
      t.integer :last_done_odometer
      t.text :notes

      t.timestamps
    end

    create_table :vehicle_logs, id: :uuid do |t|
      t.references :vehicle, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.date :date, null: false
      t.integer :odometer
      t.decimal :quantity, precision: 10, scale: 3
      t.decimal :unit_price, precision: 10, scale: 4
      t.decimal :amount, precision: 19, scale: 4, null: false, default: 0
      t.string :currency, null: false
      t.boolean :full_tank, null: false, default: true
      t.string :category
      t.references :maintenance_item, type: :uuid, foreign_key: { to_table: :vehicle_maintenance_items, on_delete: :nullify }
      t.references :entry, type: :uuid, index: { unique: true }, foreign_key: { on_delete: :nullify }
      t.text :notes

      t.timestamps
    end

    add_index :vehicle_logs, [ :vehicle_id, :date ]
    add_check_constraint :vehicle_logs, "kind IN ('fuel', 'service', 'expense')", name: "chk_vehicle_logs_kind"
    add_check_constraint :vehicle_logs, "amount >= 0", name: "chk_vehicle_logs_amount_non_negative"
  end
end
