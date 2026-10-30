# Fulas Bank: budgets as Bilance makes them. Each budget has a name and
# groups any categories or subcategories («Restaurantes y bares»: three
# subcategories of two main ones). Its amount is kept as limits, each from a
# month on: the amount of a month is that of the latest limit starting on
# or before it («Octubre y posteriores»).
#
# The monthly budgets kept until now (Budget and BudgetCategory) are turned
# into one-category budgets the first time they are needed
# (BudgetGroup::Conversion), which `budget_groups_converted_at` records.
class CreateBudgetGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :budget_groups, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :user, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :budget_group_categories, id: :uuid do |t|
      t.references :budget_group, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :category, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.timestamps
    end
    add_index :budget_group_categories, %i[budget_group_id category_id], unique: true, name: "index_budget_group_categories_unique"

    create_table :budget_group_limits, id: :uuid do |t|
      t.references :budget_group, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.date :month, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false, default: 0
      t.timestamps
    end
    add_index :budget_group_limits, %i[budget_group_id month], unique: true

    add_column :families, :budget_groups_converted_at, :datetime
  end
end
