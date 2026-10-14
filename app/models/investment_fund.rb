# Fulas Bank: an investment fund held by participaciones (units), as in the
# investments spreadsheet: its value is units × the latest price (valor
# liquidativo), typed in by the user every so often. Each price is kept in
# the fund's history (InvestmentFund::Price).
#
# The investment account holding the funds is worth what its funds are
# worth: each change of units or price updates the account's balance, as a
# balance update would.
class InvestmentFund < ApplicationRecord
  STALE_AFTER = 7.days

  belongs_to :family
  belongs_to :account
  has_many :prices, -> { order(date: :desc) }, class_name: "InvestmentFund::Price", dependent: :destroy, inverse_of: :investment_fund

  validates :name, presence: true
  validates :units, numericality: { greater_than_or_equal_to: 0 }
  validates :price, numericality: { greater_than: 0 }, allow_nil: true
  validates :cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :price_date, presence: true, if: :price
  validate :account_is_an_investment_of_the_family

  before_validation { self.isin = isin.to_s.strip.upcase.presence }

  scope :alphabetically, -> { order(:name) }

  def currency
    account&.currency || family.currency
  end

  def value
    Money.new(units.to_d * price.to_d, currency)
  end

  def cost_money
    Money.new(cost, currency) if cost
  end

  def gain
    value - cost_money if cost_money
  end

  def return_ratio
    return nil unless cost.to_d.positive?

    (gain.amount / cost.to_d).to_f
  end

  def stale?(today = Date.current)
    price_date.nil? || price_date < today - STALE_AFTER
  end

  # Saves the fund with these attributes, keeps its price in the history and
  # brings the account's balance up to date. Returns whether it was saved.
  def apply(attributes)
    previous_account = account if persisted?
    saved = transaction do
      assign_attributes(attributes)
      next false unless save

      prices.find_or_initialize_by(date: price_date).update!(price: price) if price
      true
    end

    if saved
      self.class.update_account_balance!(account)
      if previous_account && previous_account != account && self.class.exists?(account: previous_account)
        self.class.update_account_balance!(previous_account)
      end
    end
    saved
  end

  # Records a price on a date: kept in the history, and it becomes the
  # current one unless an older date is given.
  def record_price!(price, date: Date.current)
    transaction do
      prices.find_or_initialize_by(date: date).update!(price: price)
      update!(price: price, price_date: date) if price_date.nil? || date >= price_date
    end
  end

  # The account's balance becomes the sum of its funds.
  def self.update_account_balance!(account, date: Date.current)
    total = where(account: account).sum { |fund| fund.units.to_d * fund.price.to_d }
    return if (account.balance.to_d - total).abs < BigDecimal("0.01")

    account.create_reconciliation(balance: total.round(2), date: date)
  end

  private
    def account_is_an_investment_of_the_family
      return if account.nil?

      errors.add(:account, :invalid) unless account.family_id == family_id && account.accountable_type == "Investment"
    end
end
