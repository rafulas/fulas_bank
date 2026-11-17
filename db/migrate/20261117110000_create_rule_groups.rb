# Fulas Bank: rules can be put in named groups ("Supermercados", "Coche"...)
# to find them on the rules page. Deleting a group leaves its rules
# without one.
class CreateRuleGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :rule_groups, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.timestamps
    end
    add_index :rule_groups, [ :family_id, :name ], unique: true

    add_reference :rules, :rule_group, type: :uuid, foreign_key: { on_delete: :nullify }
  end
end
