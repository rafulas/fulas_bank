# Fulas Bank: categorization rules worth creating, learnt from the user's own
# history. When most movements of the same shop or concept already share a
# category (MERCADONA → Supermercado), a rule can categorize the next ones
# on its own.
#
# Movements are grouped by their merchant, or else by the significant words
# of their name ("COMPRA EN MERCADONA VALENCIA" → "MERCADONA"), separately
# for spending and income. A group becomes a suggestion when it has at least
# MIN_TRANSACTIONS categorized movements in the last LOOKBACK, one category
# holds MIN_SHARE of them, and no rule already looks for that name.
class Rule::Suggester
  MIN_TRANSACTIONS = 3
  MIN_SHARE = 0.8
  LOOKBACK = 2.years
  LIMIT = 50

  # Words that say how a movement was made, not who it was with.
  FILLER = %w[
    COMPRA COMPRAS PAGO PAGOS EN CON TARJETA TARJ ADEUDO ADEUDOS RECIBO RECIBOS CARGO CARGOS ABONO
    TRANSFERENCIA TRANSF TRASPASO BIZUM DOMICILIADO DOMICILIACION OPERACION MOVIMIENTO NUM REF
    DE DEL LA EL LOS LAS POR PARA SL SA SLU SAU ESP ESPANA SPAIN WWW COM ES HTTPS
  ].to_set.freeze

  Suggestion = Data.define(:key, :category, :transaction_type, :count, :share, :uncategorized_count, :examples) do
    def id
      "#{transaction_type}:#{key}"
    end
  end

  # The word or two a rule looks for in the name, or nil when nothing is left.
  def self.key_for(name)
    words = I18n.transliterate(name.to_s).upcase.gsub(/[^A-Z ]/, " ").split
    words = words.reject { |word| word.size < 3 || FILLER.include?(word) }
    return if words.empty?

    words.first.size >= 5 || words.size == 1 ? words.first : words.first(2).join(" ")
  end

  attr_reader :family, :entries, :dismissed, :today

  # `entries` are those the user can see; `dismissed` are ids of suggestions
  # the user does not want to see again.
  def initialize(family, entries:, dismissed: [], today: Date.current)
    @family = family
    @entries = entries
    @dismissed = Array(dismissed).to_set
    @today = today
  end

  def suggestions
    @suggestions ||= groups.filter_map { |key_and_type, rows| suggestion_for(*key_and_type, rows) }
                           .reject { |suggestion| dismissed.include?(suggestion.id) || covered?(suggestion.key) }
                           .sort_by { |suggestion| [ -suggestion.count, suggestion.key ] }
                           .first(LIMIT)
  end

  def find(id)
    suggestions.find { |suggestion| suggestion.id == id }
  end

  # Creates the suggested rule and runs it on the movements already there.
  # It only touches movements without a category, now and later, so it never
  # undoes a category chosen by hand or brought by an import.
  def accept!(suggestion)
    rule = family.rules.build(name: suggestion.key, resource_type: "transaction", active: true)
    rule.conditions.build(condition_type: "transaction_name", operator: "like", value: suggestion.key)
    rule.conditions.build(condition_type: "transaction_type", operator: "=", value: suggestion.transaction_type)
    rule.conditions.build(condition_type: "transaction_category", operator: "is_null")
    rule.actions.build(action_type: "set_transaction_category", value: suggestion.category.id.to_s)
    rule.save!
    rule.apply_later
    @suggestions = nil
    @rule_names = nil
    rule
  end

  private
    # { [key, type] => [[name, category_id], ...] }
    def groups
      rows = entries.where(entryable_type: "Transaction", date: (today - LOOKBACK)..today, excluded: false)
                    .excluding_split_parents
                    .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
                    .joins("LEFT JOIN merchants ON merchants.id = transactions.merchant_id")
                    .where.not(transactions: { kind: Transaction::TRANSFER_KINDS })
                    .pluck("entries.name", "merchants.name", "transactions.category_id", "entries.amount")

      rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(name, merchant, category_id, amount), grouped|
        key = self.class.key_for(merchant.presence || name)
        next if key.nil?

        grouped[[ key, amount.to_d.negative? ? "income" : "expense" ]] << [ name, category_id ]
      end
    end

    def suggestion_for(key, type, rows)
      categorized = rows.select { |_, category_id| category_id }
      return if categorized.size < MIN_TRANSACTIONS

      category_id, count = categorized.map(&:last).tally.max_by { |_, tally| tally }
      share = count.to_f / categorized.size
      return if share < MIN_SHARE

      category = categories[category_id]
      return if category.nil?

      Suggestion.new(
        key: key, category: category, transaction_type: type, count: count, share: share,
        uncategorized_count: rows.count { |_, id| id.nil? },
        examples: categorized.map(&:first).uniq.first(3)
      )
    end

    def categories
      @categories ||= family.categories.index_by(&:id)
    end

    # A rule already looks for this name (or a part of it).
    def covered?(key)
      rule_names.any? { |value| key.include?(value) || value.include?(key) }
    end

    def rule_names
      @rule_names ||= Rule::Condition.joins(:rule)
                                     .where(rules: { family_id: family.id }, condition_type: "transaction_name")
                                     .pluck(:value)
                                     .filter_map { |value| I18n.transliterate(value.to_s).upcase.strip.presence }
    end
end
