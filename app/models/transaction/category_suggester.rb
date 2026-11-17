# Fulas Bank: the category a movement probably goes in, from the movements
# like it that already have one: from the same merchant, or with the same
# name once case, digits and punctuation are left out ("FISIO GARCIA 03/11"
# and "Fisio García 17/11" match). Only movements in the same direction
# (spending or money in) and from the last two years count, so an old habit
# or a refund does not pull the other way.
#
# Used by the movement's detail (the categories offered first, and a one-tap
# "Aplicar" when it has none), the new movement form (as the name is typed)
# and the "Categorizar" wizard.
class Transaction::CategorySuggester
  # The most used category, how many of the movements like it have it and
  # how many there are with a category.
  Suggestion = Data.define(:category, :count, :total) do
    def share
      total.zero? ? 0 : count.to_f / total
    end
  end

  LOOKBACK = 2.years
  # A category is suggested when at least half the movements like it have it.
  MIN_SHARE = 0.5

  # The name without case, digits or punctuation, in SQL and in Ruby.
  KEY_SQL = "TRIM(REGEXP_REPLACE(LOWER(entries.name), '[^[:alpha:]]+', ' ', 'g'))".freeze

  def self.key_for(name)
    name.to_s.downcase.gsub(/[^[:alpha:]]+/, " ").strip
  end

  attr_reader :family, :scope, :today

  # `scope`: the entries the user can see (Current.accessible_entries).
  def initialize(family, scope:, today: Date.current)
    @family = family
    @scope = scope
    @today = today
  end

  # The categories used by the movements like this one, most used first:
  # [ Suggestion, ... ].
  def ranked(name:, merchant_id: nil, inflow: false, exclude_entry_id: nil, limit: 3)
    key = self.class.key_for(name)
    return [] if key.blank? && merchant_id.blank?

    counts = matching(key, merchant_id, inflow, exclude_entry_id)
             .group("transactions.category_id")
             .order(Arel.sql("COUNT(DISTINCT entries.id) DESC"))
             .count("DISTINCT entries.id")
    return [] if counts.empty?

    total = counts.values.sum
    categories = family.categories.where(id: counts.keys.first(limit)).includes(:parent).index_by(&:id)
    counts.first(limit).filter_map do |category_id, count|
      category = categories[category_id]
      Suggestion.new(category: category, count: count, total: total) if category
    end
  end

  # The one category to suggest, or nil when the movements like it are
  # split between several.
  def suggest(**options)
    best = ranked(**options, limit: 1).first
    best if best && best.share >= MIN_SHARE
  end

  # For a movement: its own name, merchant and direction.
  def suggest_for(entry)
    suggest(**options_for(entry))
  end

  def ranked_for(entry, limit: 3)
    ranked(**options_for(entry), limit: limit)
  end

  private
    def options_for(entry)
      { name: entry.name, merchant_id: entry.entryable.try(:merchant_id), inflow: entry.amount.negative?, exclude_entry_id: entry.id }
    end

    def matching(key, merchant_id, inflow, exclude_entry_id)
      relation = scope.where(entryable_type: "Transaction")
                      .excluding_split_parents
                      .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
                      .where.not(transactions: { category_id: nil })
                      .where(entries: { date: (today - LOOKBACK).. })
                      .where(inflow ? "entries.amount < 0" : "entries.amount > 0")
      relation = relation.where.not(entries: { id: exclude_entry_id }) if exclude_entry_id

      if merchant_id.present? && key.present?
        # Positional binds: the regex's [:alpha:] would read as a named one.
        relation.where("transactions.merchant_id = ? OR #{KEY_SQL} = ?", merchant_id, key)
      elsif merchant_id.present?
        relation.where(transactions: { merchant_id: merchant_id })
      else
        relation.where("#{KEY_SQL} = ?", key)
      end
    end
end
