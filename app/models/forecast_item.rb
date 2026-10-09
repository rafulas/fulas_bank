# A one-off income or expense the user expects on a future date (a tax
# refund, a trip, a renewal not set up as recurring), which the forecast adds
# on top of the recurring movements. Once its date has passed it no longer
# counts: by then the real movement is in the bank.
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
