# Fulas Bank: "Subida de recibos". The recurring payments whose price went
# up lately — the detector already records every change
# (RecurringPriceChange); this picks the recent rises of the user's active
# series and works out what each costs over a year, for Inicio. Once the
# user has seen one ("Entendido") it is not shown again.
class PriceRises
  LOOKBACK_DAYS = 45
  PREFERENCE_KEY = "dismissed_price_rises".freeze
  MAX_DISMISSED = 500

  Rise = Data.define(:change, :series) do
    def name
      series.display_name
    end

    def previous
      change.previous_amount.to_d.abs
    end

    def current
      change.new_amount.to_d.abs
    end

    def percent
      return if previous.zero?

      ((current - previous) / previous * 100).round(1)
    end

    # What the rise adds over a year at the series' pace; nil when its
    # schedule has no yearly pace.
    def annual_extra
      per_year = series.schedule.occurrences_per_year
      (current - previous) * per_year.to_d if per_year.to_f.positive?
    rescue TypeError, NoMethodError
      nil
    end

    def currency
      change.currency
    end
  end

  attr_reader :family, :user, :today

  def self.dismiss!(user, change_id)
    user.with_lock do
      preferences = (user.preferences || {}).deep_dup
      ids = Array(preferences[PREFERENCE_KEY])
      preferences[PREFERENCE_KEY] = (ids | [ change_id.to_s ]).last(MAX_DISMISSED)
      user.update!(preferences: preferences)
    end
  end

  def initialize(family, user:, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  def rises
    @rises ||= RecurringPriceChange
                 .joins(:recurring_transaction)
                 .merge(RecurringTransaction.accessible_by(user))
                 .where(recurring_transactions: { family_id: family.id, status: "active" })
                 .where(effective_on: (today - LOOKBACK_DAYS.days)..today)
                 .where("ABS(recurring_price_changes.new_amount) > ABS(recurring_price_changes.previous_amount)")
                 .where.not(id: dismissed)
                 .includes(:recurring_transaction)
                 .order(effective_on: :desc)
                 .map { |change| Rise.new(change: change, series: change.recurring_transaction) }
  end

  def any?
    rises.any?
  end

  private
    def dismissed
      Array(user.preferences&.dig(PREFERENCE_KEY))
    end
end
