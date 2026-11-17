# Fulas Bank: «Informe» of the Resumen. A user's saved choices for it (which
# accounts, which sections, which period), to open it again the same way.
class CreateReportPresets < ActiveRecord::Migration[8.1]
  def change
    create_table :report_presets, id: :uuid do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :name, null: false
      t.uuid :account_ids, array: true, null: false, default: []
      t.string :sections, array: true, null: false, default: []
      t.string :period, null: false, default: "last_month"
      t.timestamps
    end
    add_index :report_presets, %i[user_id name], unique: true
  end
end
