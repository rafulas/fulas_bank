class AddActiveToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :active, :boolean, default: true, null: false
  end
end
