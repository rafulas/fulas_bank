# Changes the user makes in the forecast table to a line the app works out by
# itself (a recurring payment on a given date, the variable spending of a
# month): another date, amount or name, or leaving it out. They are stored by
# the line's key, because the lines themselves are not stored: they are
# recalculated every time the page opens.
class CreateForecastAdjustments < ActiveRecord::Migration[8.1]
  def change
    create_table :forecast_adjustments, id: :uuid do |t|
      t.references :family, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
      t.date :date
      t.decimal :amount, precision: 19, scale: 4
      t.string :name
      t.boolean :skipped, null: false, default: false

      t.timestamps
    end

    add_index :forecast_adjustments, [ :family_id, :key ], unique: true
    add_check_constraint :forecast_adjustments, "amount IS NULL OR amount > 0", name: "chk_forecast_adjustments_amount_positive"
  end
end
