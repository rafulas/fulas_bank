# Fulas Bank: what the user chose for a row that looks like a movement they
# entered by hand with another name (TransactionImport#possible_duplicates):
# "mine" (the same movement, keeping its name), "file" (the same movement,
# taking the file's name) or "import" (a different movement). Empty is
# "mine", the likeliest.
class AddDuplicateChoiceToImportRows < ActiveRecord::Migration[8.1]
  def change
    add_column :import_rows, :duplicate_choice, :string
  end
end
