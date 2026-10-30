# Fulas Bank: turns the monthly budgets kept until now (Budget and
# BudgetCategory, one amount per category each month) into budgets of one
# category each (BudgetGroup), once per family, the first time they are
# needed.
#
# A main category with an amount becomes a budget of its own; one broken
# down into subcategories gives one budget per subcategory with an amount.
# Each month's amounts become limits, only where they change, so a budget
# keeps the amounts it had month by month.
class BudgetGroup::Conversion
  attr_reader :family

  def self.ensure!(family)
    return if family.budget_groups_converted_at.present?

    Family.transaction do
      claimed = Family.where(id: family.id, budget_groups_converted_at: nil)
                      .update_all(budget_groups_converted_at: Time.current)
      new(family).run! if claimed == 1
    end
    family.budget_groups_converted_at ||= Time.current
  end

  def initialize(family)
    @family = family
  end

  def run!
    budgets = family.budgets.where.not(budgeted_spending: nil)
                    .includes(budget_categories: :category)
                    .order(:start_date)

    budgets.group_by(&:user_id).each do |owner_id, owner_budgets|
      convert(owner_id, owner_budgets)
    end
  end

  private
    def convert(owner_id, budgets)
      groups = {}
      previous = {}

      budgets.each do |budget|
        month = budget.start_date.beginning_of_month
        amounts = amounts_of(budget)

        (amounts.keys | previous.keys).each do |category|
          amount = amounts.fetch(category, 0.to_d)
          next if amount == previous.fetch(category, 0.to_d)

          group = groups[category] ||= create_group(owner_id, category)
          group.limits.create!(month: month, amount: amount)
        end

        previous = amounts
      end
    end

    # { category => amount } of one month: the main categories with an
    # amount, or their subcategories when broken down.
    def amounts_of(budget)
      rows = budget.budget_categories.select { |row| row.category.present? && row[:budgeted_spending].to_d.positive? }
      subs, mains = rows.partition { |row| row.category.parent_id.present? }
      broken_down = subs.map { |row| row.category.parent_id }.to_set

      mains.reject { |row| broken_down.include?(row.category_id) }
           .concat(subs)
           .to_h { |row| [ row.category, row[:budgeted_spending].to_d ] }
    end

    def create_group(owner_id, category)
      group = family.budget_groups.create!(user_id: owner_id, name: category.name, position: position_of(category))
      group.group_categories.create!(category: category)
      group
    end

    def position_of(category)
      @positions ||= family.categories.sort_by(&:display_sort_key).each_with_index.to_h { |item, index| [ item.id, index ] }
      @positions.fetch(category.id, 0)
    end
end
