# Fulas Bank: a budget as Bilance makes it. It has a name and groups any
# categories or subcategories, even of different main categories
# («Restaurantes y bares»: Restaurantes, Bares and Cafeterías). A main
# category stands for all its subcategories, those created later too.
#
# A category is in one budget at most, so no spending counts twice.
#
# Its amount is kept as limits, each from a month on: a month takes the
# latest limit starting on or before it, so «Octubre y posteriores: 400 €»
# holds until a later limit changes it. Before its first limit, and with a
# limit of zero, a budget has no amount that month and is not shown.
class BudgetGroup < ApplicationRecord
  belongs_to :family
  belongs_to :user, optional: true

  has_many :group_categories, class_name: "BudgetGroupCategory", dependent: :delete_all
  has_many :categories, through: :group_categories
  has_many :limits, -> { order(:month) }, class_name: "BudgetGroupLimit", dependent: :delete_all

  validates :name, presence: true

  scope :ordered, -> { order(:position, :name) }

  # The amount of `month` (any day of it), zero when it has none.
  def limit_for(month)
    month = month.to_date.beginning_of_month
    (limits.reverse.find { |limit| limit.month <= month }&.amount || 0).to_d
  end

  # The limit set exactly on `month`, if any.
  def limit_on(month)
    limits.find { |limit| limit.month == month.to_date.beginning_of_month }
  end

  # «Octubre y posteriores»: `amount` from `month` on, replacing the limits
  # set for later months.
  def set_limit_from!(month, amount)
    month = month.to_date.beginning_of_month
    transaction do
      limits.where("month > ?", month).delete_all
      write_limit!(month, amount)
    end
    limits.reset
  end

  # `amount` for `month` only: the month after it keeps the amount it had.
  def set_month_limit!(month, amount)
    month = month.to_date.beginning_of_month
    following = month.next_month
    transaction do
      write_limit!(following, limit_for(following)) unless limit_on(following)
      write_limit!(month, amount)
    end
    limits.reset
  end

  # Each month's amount from `first` on ({ month => amount }): what is there
  # from `first` on is replaced, and only the changes are kept as limits.
  def replace_limits_from!(first, amounts)
    first = first.to_date.beginning_of_month
    transaction do
      previous = limit_for(first.prev_month)
      limits.where(month: first..).delete_all
      amounts.sort_by(&:first).each do |month, amount|
        amount = amount.to_d
        next if amount == previous

        limits.create!(month: month.to_date.beginning_of_month, amount: amount)
        previous = amount
      end
    end
    limits.reset
  end

  # The category ids chosen, as strings.
  def chosen_ids
    group_categories.map { |item| item.category_id.to_s }
  end

  # The categories chosen with the subcategories of the main ones: what the
  # budget's spending is made of.
  def expanded_category_ids
    @expanded_category_ids ||= begin
      ids = chosen_ids
      ids.empty? ? [] : ids | family.categories.where(parent_id: ids).pluck(:id).map(&:to_s)
    end
  end

  def covers?(category)
    category.present? && expanded_category_ids.include?(category.id.to_s)
  end

  # The names of the categories chosen, in the user's order.
  def category_names
    group_categories.map(&:category).compact.sort_by(&:display_sort_key).map(&:name)
  end

  # The category whose icon and colour the budget shows: the first chosen.
  def display_category
    group_categories.map(&:category).compact.min_by(&:display_sort_key)
  end

  def reload(*)
    @expanded_category_ids = nil
    super
  end

  private
    def write_limit!(month, amount)
      amount = [ amount.to_d, 0 ].max
      limit = limits.find_or_initialize_by(month: month)
      limit.update!(amount: amount)
    end
end
