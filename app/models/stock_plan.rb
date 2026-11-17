# Fulas Bank: «Plan de acciones» of the Forecast. Every year part of a bonus
# is paid in the company's shares, with one free share for every
# `gift_every` bought, and they cannot be sold for `lock_years`. Each year is
# a StockPlanGrant; the forecast expects, on the day the shares are
# delivered, the bonus cash (after the income tax withheld) and the shares'
# value in the investment account, and, once they can be sold, their sale
# into the cash account (see Forecast#stock_plan_flows).
#
# The shares are valued at the latest price the app has for the security
# (the one the investment account's holdings use), so the estimate moves
# with it.
class StockPlan < ApplicationRecord
  # How far from a past grant's day its shares bought are looked for.
  TRADE_WINDOW = 45.days

  belongs_to :family
  belongs_to :investment_account, class_name: "Account"
  belongs_to :security
  belongs_to :cash_account, class_name: "Account", optional: true
  has_many :grants, -> { order(:granted_on) }, class_name: "StockPlanGrant", dependent: :destroy, inverse_of: :stock_plan

  validates :name, :currency, presence: true
  validates :base_bonus, numericality: { greater_than_or_equal_to: 0 }
  validates :stock_percent, :tax_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :gift_every, :lock_years, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :accounts_are_the_familys

  before_validation :inherit_currency

  scope :alphabetically, -> { order(:name) }

  # The latest stored price of a share, in the plan's currency (nil if the
  # app has none).
  def price
    return @price if defined?(@price)

    @price = price_record && to_plan_currency(price_record.price, price_record.currency)
  end

  def price_date
    price_record&.date
  end

  # The shares of the security bought in the investment account around
  # `date` (free ones included): what a past year's grant delivered.
  def traded_shares_around(date)
    Trade.joins(:entry)
         .where(entries: { account_id: investment_account_id, date: (date - TRADE_WINDOW)..(date + TRADE_WINDOW) })
         .where(security_id: security_id)
         .where("trades.qty > 0")
         .sum(:qty)
         .to_d
  end

  private
    def price_record
      return @price_record if defined?(@price_record)

      @price_record = security&.latest_price
    end

    def to_plan_currency(amount, from)
      return amount.to_d if from.blank? || from == currency

      Money.new(amount, from).exchange_to(currency).amount
    rescue Money::ConversionError
      amount.to_d
    end

    def inherit_currency
      self.currency ||= investment_account&.currency
    end

    def accounts_are_the_familys
      errors.add(:investment_account, :invalid) if investment_account && investment_account.family_id != family_id
      errors.add(:cash_account, :invalid) if cash_account && cash_account.family_id != family_id
    end
end
