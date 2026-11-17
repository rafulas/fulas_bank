# A one-off income or expense the user expects on a future date (a tax
# refund, a trip, a renewal not set up as recurring), which the forecast adds
# on top of the recurring movements. It is added from the Forecast, or as a
# new transaction with a date after today (Transacciones). Fulas Bank: the
# bank's statements are imported by hand, days late, so once its date has
# passed it is still expected until a movement of that day or later is
# imported in its account (see Forecast#expected_date): by then the real
# movement is in the bank.
#
# Fulas Bank: it can also be a transfer between two of the user's accounts
# (nature "transfer"): it leaves `account` and reaches `destination_account`
# on the same day, so the total does not change.
class ForecastItem < ApplicationRecord
  include Monetizable

  NATURES = %w[outflow inflow transfer].freeze

  monetize :amount

  belongs_to :family
  belongs_to :account
  belongs_to :destination_account, class_name: "Account", optional: true

  validates :name, :date, :currency, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :nature, inclusion: { in: NATURES }
  validate :account_belongs_to_family
  validate :destination_is_another_account, if: :transfer?

  before_validation :inherit_currency
  before_validation :forget_destination, unless: :transfer?

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

  def inflow?
    nature == "inflow"
  end

  def transfer?
    nature == "transfer"
  end

  # In the bank's convention, like an entry: positive when money goes out.
  # A transfer goes out of `account`.
  def signed_amount
    outflow? || transfer? ? amount : -amount
  end

  private
    def inherit_currency
      self.currency ||= account&.currency
    end

    def account_belongs_to_family
      return if account.blank? || account.family_id == family_id

      errors.add(:account, :invalid)
    end

    def forget_destination
      self.destination_account = nil
    end

    # Both accounts are the family's, they are not the same one, and they
    # share a currency (the amount is the same on both sides).
    def destination_is_another_account
      if destination_account.blank? || destination_account.family_id != family_id
        errors.add(:destination_account, :blank)
      elsif destination_account_id == account_id
        errors.add(:destination_account, :same_account)
      elsif account && destination_account.currency != account.currency
        errors.add(:destination_account, :other_currency)
      end
    end
end
