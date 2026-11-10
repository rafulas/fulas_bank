# Fulas Bank: car expenses linked to a bank charge in «Leasing» were filed as
# «Otros», which counts as a running cost on top of the value the car has lost
# since it was bought: its purchase counted twice. They are what paid for the
# car, so they become «Compra del vehículo» (Vehicle::Log, category
# "purchase"), as AssetLinker files them from now on. Only those still in
# «Otros»: one the user moved to another type stays as it is.
class MoveLeasingVehicleLogsToPurchase < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE vehicle_logs
      SET category = 'purchase', updated_at = NOW()
      FROM entries
      JOIN transactions ON entries.entryable_type = 'Transaction' AND transactions.id = entries.entryable_id
      JOIN categories ON categories.id = transactions.category_id
      WHERE vehicle_logs.entry_id = entries.id
        AND vehicle_logs.kind = 'expense'
        AND vehicle_logs.category = 'other'
        AND LOWER(categories.name) = 'leasing'
    SQL
  end

  def down
    # Nothing to undo: which of them were «Otros» before is not kept.
  end
end
