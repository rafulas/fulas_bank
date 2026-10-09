# One-off income or expenses the user knows are coming (a tax refund, a
# trip, an insurance renewal not set up as recurring...). The forecast adds
# them on their date, on top of the recurring movements.
class CreateForecastItems < ActiveRecord::Migration[8.1]
  def change
    create_table :forecast_items, id: :uuid do |t|
      t.references :family, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.date :date, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :nature, null: false, default: "outflow"
      t.string :currency, null: false
      t.text :notes

      t.timestamps
    end

    add_index :forecast_items, [ :family_id, :date ]
    add_check_constraint :forecast_items, "amount > 0", name: "chk_forecast_items_amount_positive"
    add_check_constraint :forecast_items, "nature IN ('inflow', 'outflow')", name: "chk_forecast_items_nature"
  end
end
