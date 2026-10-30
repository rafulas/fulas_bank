# Fulas Bank: a budget's amount from a month on (see BudgetGroup).
class BudgetGroupLimit < ApplicationRecord
  belongs_to :budget_group

  validates :month, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }

  before_validation { self.month = month&.beginning_of_month }
end
