# Fulas Bank: a transaction import can read the merchant from its own column
# (Bilance's «Comercio»). The import keeps which column that is, and each row
# the merchant read from it.
class AddMerchantToImports < ActiveRecord::Migration[8.1]
  def change
    add_column :imports, :merchant_col_label, :string
    add_column :import_rows, :merchant, :string
  end
end
