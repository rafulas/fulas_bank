# Fulas Bank: the movements like this one, as Bilance shows them under a
# movement: from the same merchant, or, without one, with the same name
# (ignoring case and spaces). Newest first, in the accounts the user can see.
#
# They show which of them are payments of a recurring series, so it is easy
# to tell an Apple subscription from a one-off purchase in the same shop.
class Transaction::Similar
  LIMIT = 8

  attr_reader :entry

  def initialize(entry, scope:, limit: LIMIT)
    @entry = entry
    @scope = scope
    @limit = limit
  end

  # @return [Array<Entry>] with their category, tags and recurring payments loaded
  def entries
    @entries ||= begin
      transaction = entry.transaction
      candidates = @scope.where(entryable_type: "Transaction")
                         .excluding_split_parents
                         .where.not(id: entry.id)
                         .joins("INNER JOIN transactions similar_t ON similar_t.id = entries.entryable_id")

      candidates = if transaction.merchant_id.present?
        candidates.where("similar_t.merchant_id = :merchant OR LOWER(TRIM(entries.name)) = :name",
                         merchant: transaction.merchant_id, name: normalized_name)
      else
        candidates.where("LOWER(TRIM(entries.name)) = ?", normalized_name)
      end

      candidates.order(date: :desc, created_at: :desc)
                .limit(@limit)
                .preload(:account, recurring_allocations: { recurring_occurrence: :recurring_transaction },
                         entryable: [ :tags, { category: :parent } ])
                .to_a
    end
  end

  def any?
    normalized_name.present? && entries.any?
  end

  private
    def normalized_name
      entry.name.to_s.strip.downcase
    end
end
