class AddPurchaseToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :purchase_price, :decimal, precision: 19, scale: 4
    add_column :vehicles, :purchase_date, :date
  end
end
