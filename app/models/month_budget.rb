# Fulas Bank: the budgets of a month, as Bilance does them (see BudgetGroup):
# each one a name, the categories it groups and an amount from a month on.
# The month's total is the sum of its budgets.
#
# What a budget has spent is what went out in its categories that month,
# minus what came back (refunds), never below zero. Left out, as in the
# rest of the budget: transfers, one-off purchases ("Transacción puntual"),
# movements excluded by hand and accounts left out of reports.
#
# The budgets kept month by month until now are turned into one-category
# budgets the first time (BudgetGroup::Conversion).
class MonthBudget
  attr_reader :family, :user, :month

  # The owner of the budgets: nobody (the household's), unless the family
  # keeps personal budgets.
  def self.owner_id(family, user)
    family.personal_budgets? && user ? user.id : nil
  end

  def initialize(family, user:, month: Date.current)
    @family = family
    @user = user
    @month = month.to_date.beginning_of_month
  end

  # Every budget, with an amount this month or not, in the user's order.
  def groups
    @groups ||= begin
      BudgetGroup::Conversion.ensure!(family)
      family.budget_groups.where(user_id: owner_id).ordered
            .includes(:limits, group_categories: :category).to_a
    end
  end

  # The budgets with an amount this month.
  def budgeted_groups
    groups.select { |group| group.limit_for(month).positive? }
  end

  # { budget id => amount } this month, positive amounts only.
  def amounts
    budgeted_groups.to_h { |group| [ group.id, group.limit_for(month) ] }
  end

  def find_group(id)
    groups.find { |group| group.id == id.to_s }
  end

  # The budget a movement of `category` counts in, if any.
  def group_for(category)
    groups.find { |group| group.covers?(category) }
  end

  # What a budget has spent this month.
  def spent(group)
    [ group.expanded_category_ids.sum { |id| spending_by_category.fetch(id, 0.to_d) }, 0 ].max
  end

  # { category id => spending } this month in the budgeted categories, or
  # in `category_ids` (refunds take it down).
  def spending_by_category(category_ids = nil)
    return category_spending(category_ids) if category_ids

    @spending_by_category ||= category_spending(budgeted_category_ids)
  end

  # { date => spending } in the budgeted categories (or `category_ids`),
  # from the first of the month to `last_day`, for the pace chart.
  def daily_spending(last_day, category_ids = budgeted_category_ids)
    spending_scope(month..last_day, category_ids)
      .group(Arel.sql("entries.date")).sum(Arel.sql(amount_sql))
      .to_h { |date, amount| [ date.to_date, amount.to_d ] }
  end

  # { month => what `group` spent } for each of `months` (firsts of month).
  def monthly_spending(group, months)
    return {} if months.empty?

    rows = spending_scope(months.min..months.max.end_of_month, group.expanded_category_ids)
             .group(Arel.sql("date_trunc('month', entries.date)")).sum(Arel.sql(amount_sql))
    by_month = rows.to_h { |date, amount| [ date.to_date.beginning_of_month, amount.to_d ] }
    months.index_with { |item| [ by_month.fetch(item, 0.to_d), 0 ].max }
  end

  # The month's movements that count in `group`, newest first.
  def entries_for(group)
    spending_scope(month..month.end_of_month, group.expanded_category_ids)
      .includes(:account, entryable: :category)
      .order(date: :desc, created_at: :desc)
  end

  # The categories already in a budget other than `except`: each category
  # goes in one budget at most.
  def taken_ids(except: nil)
    groups.reject { |group| group == except }.flat_map(&:expanded_category_ids).to_set
  end

  # «Este mes y posteriores»: { budget id => amount } from this month on.
  # A budget left out keeps its amounts.
  def save!(new_amounts)
    BudgetGroup.transaction do
      new_amounts.to_h.each do |id, value|
        group = find_group(id)
        next unless group

        amount = parse(value)
        group.set_limit_from!(month, amount) unless amount == group.limit_for(month) && group.limits.none? { |limit| limit.month > month }
      end
    end
    reset!
    true
  end

  # A budget for each main category given an amount ({ category id =>
  # amount }), named as the category, from this month on.
  def create_for_categories!(new_amounts)
    free = categories.reject { |category| taken_ids.include?(category.id.to_s) }.index_by { |category| category.id.to_s }
    BudgetGroup.transaction do
      new_amounts.to_h.each do |id, value|
        category = free[id.to_s]
        amount = parse(value)
        next unless category && amount.positive?

        group = family.budget_groups.new(user_id: owner_id, name: category.name, position: next_position)
        group.group_categories.build(category: category)
        group.save!
        group.set_limit_from!(month, amount)
      end
    end
    reset!
  end

  # Saves a budget's name, categories and amount from this month on.
  # A main category chosen takes in its subcategories, so they are not kept
  # apart; a category already in another budget is refused.
  #
  # @return [Boolean] false with the errors on the budget
  def assign(group, name:, category_ids:, amount:)
    group.name = name.to_s.strip
    chosen = normalize(category_ids)
    taken = taken_ids(except: group)
    clash = chosen.flat_map { |category| [ category, *subcategories_of(category) ] }.find { |category| taken.include?(category.id.to_s) }

    problems = []
    problems << I18n.t("month_budget.errors.no_categories") if chosen.empty?
    problems << I18n.t("month_budget.errors.taken", category: clash.name, budget: group_for(clash)&.name) if clash
    valid = group.valid?
    problems.each { |problem| group.errors.add(:base, problem) }
    return false unless valid && problems.empty?

    BudgetGroup.transaction do
      group.position = next_position if group.new_record?
      group.user_id = owner_id if group.new_record?
      group.save!
      group.group_categories.where.not(category_id: chosen.map(&:id)).delete_all
      (chosen.map(&:id) - group.group_categories.reload.map(&:category_id)).each do |id|
        group.group_categories.create!(category_id: id)
      end
      group.group_categories.reset
      group.reload
      amount = parse(amount)
      group.set_limit_from!(month, amount) if amount != group.limit_for(month) || group.limits.none?
    end
    reset!
    true
  end

  # The main categories a budget can group, in the user's order.
  def categories
    @categories ||= family.categories.roots.reject(&:analytics_neutral?).sort_by(&:display_sort_key)
  end

  # The subcategories of a main category.
  def subcategories_of(category)
    subcategories_by_parent.fetch(category.id, [])
  end

  # Every category a budget can group: the main ones and their subcategories.
  def category_ids
    categories.map(&:id) + subcategories_by_parent.values.flatten.map(&:id)
  end

  private
    def owner_id
      self.class.owner_id(family, user)
    end

    def reset!
      @groups = @spending_by_category = nil
    end

    def next_position
      (groups.map(&:position).max || -1) + 1
    end

    def parse(value)
      [ value.to_s.strip.delete(" €").then { |raw| raw.include?(",") ? raw.delete(".").tr(",", ".") : raw }.to_d, 0 ].max
    end

    # The chosen categories that can be grouped, a subcategory dropped when
    # its main category is chosen too.
    def normalize(ids)
      wanted = Array(ids).map(&:to_s).to_set
      allowed = categories + subcategories_by_parent.values.flatten
      chosen = allowed.select { |category| wanted.include?(category.id.to_s) }
      main_ids = chosen.reject(&:parent_id).map(&:id).to_set
      chosen.reject { |category| category.parent_id && main_ids.include?(category.parent_id) }
    end

    def subcategories_by_parent
      @subcategories_by_parent ||= family.categories.where(parent_id: categories.map(&:id))
                                         .reject(&:analytics_neutral?)
                                         .sort_by(&:display_sort_key)
                                         .group_by(&:parent_id)
    end

    def category_spending(category_ids)
      spending_scope(month..month.end_of_month, category_ids)
        .group("t.category_id").sum(Arel.sql(amount_sql))
        .to_h { |id, amount| [ id.to_s, amount.to_d ] }
    end

    def budgeted_category_ids
      budgeted_groups.flat_map(&:expanded_category_ids).uniq
    end

    def report_account_ids
      @report_account_ids ||= begin
        accounts = family.accounts.included_in_reports
        accounts = accounts.accessible_by(user) if user
        accounts.pluck(:id)
      end
    end

    def amount_sql
      "entries.amount * COALESCE(budget_rates.rate, 1)"
    end

    def spending_scope(range, category_ids)
      return Entry.none if category_ids.empty?

      family.entries
            .excluding_split_parents
            .where(account_id: report_account_ids, entryable_type: "Transaction", excluded: false, date: range)
            .joins("INNER JOIN transactions t ON t.id = entries.entryable_id")
            .joins(ActiveRecord::Base.sanitize_sql_array([
              "LEFT JOIN exchange_rates budget_rates ON (budget_rates.date = entries.date AND budget_rates.from_currency = entries.currency AND budget_rates.to_currency = ?)",
              family.currency
            ]))
            .where("t.kind NOT IN (?) OR t.id IN (#{Transaction::INVESTMENT_WITHDRAWAL_IDS_SQL})", Transaction::BUDGET_EXCLUDED_KINDS)
            .where("t.category_id IN (?)", category_ids)
    end
end
