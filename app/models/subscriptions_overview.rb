# Fulas Bank: the "Suscripciones" page, like Bilance's subscription cost
# calculator but with the user's real subscriptions (recurring series of type
# "subscription"): what they cost a month, a year and in five years, and how
# much would be saved by dropping the ones marked "podría quitarla".
#
# Prices are each series' monthly equivalent (a yearly 59,88 € counts as
# 4,99 € a month), at today's prices: no inflation or price rises ahead.
# The "could drop" marks are the user's own, kept in their preferences.
#
# Only what can be cancelled is a subscription here: insurance, loans or
# utilities never are, nor are they offered as candidates (see
# RecurringTransaction::Classifier.obligatory?). Cancelling one pauses its
# series, so it leaves the totals, the Forecast and Planes; taking it up
# again makes it active once more.
class SubscriptionsOverview
  COULD_DROP_PREFERENCE = "subscriptions_could_drop".freeze
  YEARS = 5

  Row = Data.define(:series, :monthly, :could_drop, :last_paid_on, :price_change)

  attr_reader :family, :user

  def initialize(family, user:)
    @family = family
    @user = user
  end

  def currency
    family.currency
  end

  def rows
    @rows ||= subscriptions.map do |series|
      Row.new(
        series: series,
        monthly: to_family_currency(series.monthly_equivalent_amount),
        could_drop: could_drop_ids.include?(series.id),
        last_paid_on: last_paid_on[series.id],
        price_change: series.recent_price_changes(1).first&.then { |change| change if change.effective_on >= Date.current << 12 }
      )
    end.sort_by { |row| -row.monthly.amount }
  end

  def monthly
    sum(rows.map(&:monthly))
  end

  def yearly
    monthly * 12
  end

  def five_years
    yearly * YEARS
  end

  # What dropping the marked ones would save a year.
  def could_save_yearly
    sum(rows.select(&:could_drop).map(&:monthly)) * 12
  end

  # Active recurring payments not marked as subscriptions, which may be one.
  # What must be paid anyway (insurance, a loan, the power bill) is left out.
  def other_candidates
    family.recurring_transactions.accessible_by(user).active
          .where(bill_type: %w[bill other]).where(destination_account_id: nil).where("amount > 0")
          .includes(:merchant, category: :parent).order(:name).to_a
          .reject { |series| RecurringTransaction::Classifier.obligatory?(series) }
          .first(20)
  end

  # Subscriptions cancelled (paused) or retired, newest first, to take up again.
  def cancelled
    @cancelled ||= family.recurring_transactions.accessible_by(user).typed_subscription
                         .where(status: %w[paused inactive]).includes(:merchant)
                         .order(Arel.sql("cancelled_on DESC NULLS LAST"), :name).to_a
  end

  def self.cancel!(series)
    series.update!(status: "paused", cancelled_on: Date.current)
  end

  def self.resume!(series)
    series.update!(status: "active", cancelled_on: nil)
  end

  def self.toggle_could_drop!(user, series_id, value)
    ids = Array(user.preferences&.dig(COULD_DROP_PREFERENCE))
    ids = value ? (ids | [ series_id ]) : (ids - [ series_id ])
    user.update_dashboard_preferences(COULD_DROP_PREFERENCE => ids)
  end

  private
    def subscriptions
      family.recurring_transactions.accessible_by(user).active.typed_subscription
            .includes(:merchant, :recurring_price_changes, :recurrence_rules).to_a
    end

    def could_drop_ids
      @could_drop_ids ||= Array(user.preferences&.dig(COULD_DROP_PREFERENCE))
    end

    # { series id => date of the last payment matched to it }
    def last_paid_on
      @last_paid_on ||= RecurringAllocation.joins(:recurring_occurrence)
                                           .where(recurring_occurrences: { recurring_transaction_id: subscriptions.map(&:id) })
                                           .group("recurring_occurrences.recurring_transaction_id")
                                           .maximum(:paid_on)
    end

    def sum(list)
      Money.new(list.sum(0.to_d) { |money| money.amount }, currency)
    end

    def to_family_currency(money)
      return money if money.currency.iso_code == currency

      money.exchange_to(currency)
    rescue Money::ConversionError
      Money.new(money.amount, currency)
    end
end
