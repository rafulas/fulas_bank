# Fulas Bank: a transaction import leaves out the rows dated after today (a
# movement that has not happened yet, like a payday already noted in
# Bilance) and says how many it left out.
class AddSkippedFutureRowsCountToImports < ActiveRecord::Migration[8.1]
  def change
    add_column :imports, :skipped_future_rows_count, :integer, default: 0, null: false
  end
end
