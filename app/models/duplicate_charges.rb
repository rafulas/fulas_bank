# Fulas Bank: possible double charges, after FlowVista: two expenses in the
# same account, for the same amount, from the same merchant (or with the
# same description), on the same day or the next. The app already merges a
# bank's pending charge with its posted one; this catches the charges that
# were really taken twice, so the user can check them.
#
# A pair the user says is fine is remembered in their preferences and not
# shown again.
class DuplicateCharges
  LOOKBACK_DAYS = 60
  MAX_GAP_DAYS = 1
  PREFERENCE_KEY = "dismissed_duplicate_charges".freeze

  Pair = Data.define(:first, :second) do
    def key
      [ first.id, second.id ].sort.join(":")
    end

    def amount
      first.amount_money
    end

    def name
      first.entryable.merchant&.name.presence || first.name
    end

    def account
      first.account
    end
  end

  attr_reader :family, :user, :today

  def initialize(family, user:, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  def self.dismiss!(user, key)
    user.with_lock do
      preferences = (user.preferences || {}).deep_dup
      keys = Array(preferences[PREFERENCE_KEY])
      preferences[PREFERENCE_KEY] = (keys | [ key.to_s ]).last(500)
      user.update!(preferences: preferences)
    end
  end

  def pairs
    @pairs ||= candidates.group_by { |entry| group_key(entry) }.values.flat_map { |entries| pairs_in(entries) }
                         .reject { |pair| dismissed.include?(pair.key) }
                         .sort_by { |pair| -pair.second.date.jd }
  end

  def any?
    pairs.any?
  end

  private
    def candidates
      family.entries
            .visible
            .where(account_id: user.accessible_accounts.select(:id))
            .excluding_pending
            .excluding_split_parents
            .where(entryable_type: "Transaction", excluded: false, date: (today - LOOKBACK_DAYS)..today)
            .where("entries.amount > 0")
            .joins("INNER JOIN transactions dup_t ON dup_t.id = entries.entryable_id")
            .where("dup_t.kind = ?", "standard")
            .preload(:account, entryable: :merchant)
            .to_a
    end

    def group_key(entry)
      label = entry.entryable.merchant_id || entry.name.to_s.downcase.squish
      [ entry.account_id, entry.currency, entry.amount.to_d, label ]
    end

    # Neighbours by date at most MAX_GAP_DAYS apart; each charge in one pair.
    def pairs_in(entries)
      sorted = entries.sort_by { |entry| [ entry.date, entry.created_at ] }
      result = []
      index = 0
      while index < sorted.size - 1
        first, second = sorted[index], sorted[index + 1]
        if (second.date - first.date).to_i <= MAX_GAP_DAYS
          result << Pair.new(first: first, second: second)
          index += 2
        else
          index += 1
        end
      end
      result
    end

    def dismissed
      @dismissed ||= Array(user.preferences&.dig(PREFERENCE_KEY)).to_set
    end
end
