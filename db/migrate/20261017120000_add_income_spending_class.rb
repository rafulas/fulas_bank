# Fulas Bank: "income" joins the spending classes (see Category::SpendingClass)
# to mark the categories whose money in is income. Money coming in to any
# other category is a refund: it lowers that category's spending instead of
# counting as income (a Sanitas reimbursement lowers "Atención médica").
# Existing families get it on their "Ingresos" main category.
class AddIncomeSpendingClass < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :categories, name: "chk_categories_spending_class"
    add_check_constraint :categories, "spending_class IS NULL OR spending_class IN ('essential', 'discretionary', 'savings', 'income')",
                         name: "chk_categories_spending_class"

    execute "UPDATE categories SET spending_class = 'income' WHERE name = 'Ingresos' AND parent_id IS NULL AND spending_class IS NULL"
  end

  def down
    execute "UPDATE categories SET spending_class = NULL WHERE spending_class = 'income'"
    remove_check_constraint :categories, name: "chk_categories_spending_class"
    add_check_constraint :categories, "spending_class IS NULL OR spending_class IN ('essential', 'discretionary', 'savings')",
                         name: "chk_categories_spending_class"
  end
end
