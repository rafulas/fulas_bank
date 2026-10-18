# A one-off income or expense the user expects on a future date (a tax
# refund, a trip, a renewal not set up as recurring), which the forecast adds
# on top of the recurring movements. It is added from the Forecast, or as a
# new transaction with a date after today (Transacciones). Fulas Bank: the
# bank's statements are imported by hand, days late, so once its date has
# passed it is still expected until a movement of that day or later is
# imported in its account (see Forecast#expected_date): by then the real
# movement is in the bank.
class ForecastItem < ApplicationRecord
  include Monetizable

  NATURES = %w[outflow inflow].freeze

  monetize :amount

  belongs_to :family
  belongs_to :account

  validates :name, :date, :currency, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :nature, inclusion: { in: NATURES }
  validate :account_belongs_to_family

  before_validation :inherit_currency

  scope :chronological, -> { order(:date, :created_at) }
  scope :upcoming, -> { where("forecast_items.date > ?", Date.current) }

  # Fulas Bank: the ones still expected on `today`: those still to come, and
  # those whose day has passed (up to Forecast::OVERDUE_LOOKBACK ago) while
  # no movement of that day or later has been imported in their account.
  def self.pending(today: Date.current)
    items = where(date: (today - Forecast::OVERDUE_LOOKBACK)..).includes(:account).to_a
    overdue_accounts = items.select { |item| item.date <= today }.map(&:account_id).uniq
    last_imported = overdue_accounts.any? ? Entry.where(account_id: overdue_accounts, date: ..today).group(:account_id).maximum(:date) : {}

    items.select do |item|
      next true if item.date > today

      last = last_imported[item.account_id]
      last.present? && item.date > last
    end.sort_by { |item| [ item.date, item.created_at ] }
  end

  # Due on a day already passed, waiting for the bank's statement.
  def overdue?(today: Date.current)
    date <= today
  end

  def outflow?
    nature == "outflow"
  end

  # In the bank's convention, like an entry: positive when money goes out.
  def signed_amount
    outflow? ? amount : -amount
  end

  private
    def inherit_currency
      self.currency ||= account&.currency
    end

    def account_belongs_to_family
      return if account.blank? || account.family_id == family_id

      errors.add(:account, :invalid)
    end
end
