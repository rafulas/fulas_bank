# Fulas Bank: a one-off movement typed in the Forecast can be a transfer
# between two of the user's accounts: it leaves one and reaches the other.
class AddDestinationAccountToForecastItems < ActiveRecord::Migration[8.1]
  def change
    add_reference :forecast_items, :destination_account, type: :uuid, foreign_key: { to_table: :accounts, on_delete: :cascade }

    remove_check_constraint :forecast_items, "nature::text = ANY (ARRAY['inflow'::character varying::text, 'outflow'::character varying::text])",
                            name: "chk_forecast_items_nature"
    add_check_constraint :forecast_items, "nature IN ('inflow', 'outflow', 'transfer')", name: "chk_forecast_items_nature"
    add_check_constraint :forecast_items, "(nature = 'transfer') = (destination_account_id IS NOT NULL)",
                         name: "chk_forecast_items_transfer_destination"
  end
end
