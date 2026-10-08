class AddSpecialAndPositionToCategories < ActiveRecord::Migration[8.1]
  def change
    # Marks the three Fulas Bank categories with a built-in behavior
    # ("other", "excluded", "transfers"). The behavior follows this column,
    # not the name, so they can be renamed or restyled freely.
    add_column :categories, :special, :string
    # Display order inside its level (root categories, or the subcategories of
    # one parent). Categories without a position sort after, by name.
    add_column :categories, :position, :integer

    add_index :categories, [ :family_id, :special ], unique: true, where: "special IS NOT NULL"
  end
end
