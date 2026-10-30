# Fulas Bank: what the user decides about the categories of "Gastos varios",
# chosen in «Ver cálculo»:
#
#   - categories left out of the forecast altogether ("No prever"), such as
#     one-off renovations: their spending is not averaged in any month;
#   - a category planned for one month ("En noviembre, Viajes: 0 €"): that
#     month its usual spending is replaced by the amount given. Travelling is
#     usual, but not this November.
#
# A category stands for its subcategories too. Both are kept in the user's
# preferences, like the accounts left out of "Gastos varios".
class Forecast::VariablePlan
  EXCLUDED_PREFERENCE = "forecast_variable_excluded_categories".freeze
  PLANS_PREFERENCE = "forecast_variable_category_plans".freeze

  # A category's amount for one month.
  Plan = Data.define(:month, :category_id, :amount)

  attr_reader :family, :user, :today

  def initialize(family, user: nil, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  # The categories chosen as left out (not their subcategories).
  def excluded_ids
    @excluded_ids ||= Array(preferences[EXCLUDED_PREFERENCE]).map(&:to_s) & category_ids
  end

  # Those categories with their subcategories: what the estimate leaves out.
  def excluded_with_children
    @excluded_with_children ||= with_children(excluded_ids)
  end

  def excluded?(category_id)
    excluded_ids.include?(category_id.to_s)
  end

  # Every plan kept for this month or a later one.
  def plans
    @plans ||= Array(preferences[PLANS_PREFERENCE]).filter_map do |item|
      month = Date.parse(item["month"].to_s).beginning_of_month
      category_id = item["category_id"].to_s
      next unless category_ids.include?(category_id) && month >= today.beginning_of_month

      Plan.new(month: month, category_id: category_id, amount: item["amount"].to_d.abs)
    rescue Date::Error
      nil
    end
  end

  def plans_for(month)
    plans.select { |plan| plan.month == month.beginning_of_month }
  end

  def plan_for(month, category_id)
    plans_for(month).find { |plan| plan.category_id == category_id.to_s }
  end

  # The categories planned for `month`, with their subcategories: the
  # month's average leaves them out, because the plan replaces them.
  def planned_ids(month)
    with_children(plans_for(month).map(&:category_id))
  end

  # What the plans add to `month`.
  def planned_total(month)
    plans_for(month).sum(&:amount).to_d
  end

  def exclude!(category_id)
    save!(EXCLUDED_PREFERENCE => (excluded_ids | [ category_id.to_s ]))
  end

  def include!(category_id)
    save!(EXCLUDED_PREFERENCE => excluded_ids - [ category_id.to_s ])
  end

  def plan!(month, category_id, amount)
    others = stored_plans.reject { |item| same?(item, month, category_id) }
    save!(PLANS_PREFERENCE => others + [ { "month" => month.beginning_of_month.iso8601, "category_id" => category_id.to_s, "amount" => amount.to_d.abs.to_s } ])
  end

  def unplan!(month, category_id)
    save!(PLANS_PREFERENCE => stored_plans.reject { |item| same?(item, month, category_id) })
  end

  # A category with its subcategories, as ids.
  def with_children(ids)
    ids = Array(ids).map(&:to_s)
    return [] if ids.empty?

    ids | family.categories.where(parent_id: ids).pluck(:id).map(&:to_s)
  end

  private
    def preferences
      user&.preferences || {}
    end

    def stored_plans
      Array(preferences[PLANS_PREFERENCE])
    end

    def same?(item, month, category_id)
      item["month"].to_s == month.beginning_of_month.iso8601 && item["category_id"].to_s == category_id.to_s
    end

    def category_ids
      @category_ids ||= family.categories.pluck(:id).map(&:to_s)
    end

    def save!(prefs)
      user.update_dashboard_preferences(prefs)
      @excluded_ids = @excluded_with_children = @plans = nil
    end
end
