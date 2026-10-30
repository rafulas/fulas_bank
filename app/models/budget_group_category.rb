# Fulas Bank: a category (main or subcategory) a budget groups (BudgetGroup).
class BudgetGroupCategory < ApplicationRecord
  belongs_to :budget_group
  belongs_to :category
end
