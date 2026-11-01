# Fulas Bank: movements that may have been entered twice, for the list's
# «Duplicados» filter: two movements with the same amount (and currency)
# and the same category, or both without one, at most a day apart (a
# statement and a hand entry may disagree by a day). Any account the user
# can reach: a movement imported into the wrong account shows too.
#
# Split parents (their parts are the movements) and the two sides of one
# transfer (opposite amounts) never match. A pair the user says is fine
# («No son duplicados») is kept in their preferences with those of Inicio
# (DuplicateCharges) and not shown again.
class Transaction::DuplicateFinder
  MAX_GAP_DAYS = 1

  attr_reader :family, :account_ids, :user

  def initialize(family, account_ids:, user: nil)
    @family = family
    @account_ids = account_ids
    @user = user
  end

  # [[entry id, entry id], ...], each pair once, without the dismissed ones.
  def pairs
    @pairs ||= raw_pairs.reject { |pair| dismissed.include?(key(pair)) }
  end

  # The ids of every movement in a pair.
  def entry_ids
    pairs.flatten.uniq
  end

  # Says the pairs among `ids` are fine. @return [Integer] pairs dismissed
  def dismiss!(ids)
    ids = Array(ids).map(&:to_s).to_set
    keys = pairs.select { |pair| pair.all? { |id| ids.include?(id) } }.map { |pair| key(pair) }
    DuplicateCharges.dismiss!(user, keys) if user && keys.any?
    keys.size
  end

  def key(pair)
    pair.sort.join(":")
  end

  private
    def raw_pairs
      return [] if account_ids.blank?

      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, { account_ids: account_ids, gap: MAX_GAP_DAYS } ])
        SELECT a.id, b.id
        FROM entries a
        INNER JOIN transactions ta ON ta.id = a.entryable_id
        INNER JOIN entries b ON b.entryable_type = 'Transaction'
                            AND b.id > a.id
                            AND b.amount = a.amount
                            AND b.currency = a.currency
                            AND b.date BETWEEN a.date - :gap AND a.date + :gap
                            AND b.account_id IN (:account_ids)
        INNER JOIN transactions tb ON tb.id = b.entryable_id
        WHERE a.entryable_type = 'Transaction'
          AND a.account_id IN (:account_ids)
          AND ta.category_id IS NOT DISTINCT FROM tb.category_id
          AND NOT EXISTS (SELECT 1 FROM entries child WHERE child.parent_entry_id = a.id)
          AND NOT EXISTS (SELECT 1 FROM entries child WHERE child.parent_entry_id = b.id)
      SQL

      ActiveRecord::Base.connection.select_rows(sql).map { |first, second| [ first.to_s, second.to_s ] }
    end

    def dismissed
      @dismissed ||= Array(user&.preferences&.dig(DuplicateCharges::PREFERENCE_KEY)).to_set
    end
end
