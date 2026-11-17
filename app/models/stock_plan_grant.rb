# Fulas Bank: one year of a StockPlan: the bonus paid on `granted_on`
# (`achievement_percent` of the plan's base, part of it in shares) and the
# sale of those shares on `sell_on`, once they can be sold.
#
# The shares come from what the user typed once they were delivered, from
# the trades in the investment account for a past year (free ones
# included), or else are worked out: the part of the bonus in shares at the
# latest price, rounded down, plus one free share for every `gift_every`.
class StockPlanGrant < ApplicationRecord
  belongs_to :stock_plan

  validates :granted_on, :sell_on, presence: true
  validates :achievement_percent, numericality: { greater_than_or_equal_to: 0 }
  validates :stock_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :shares, :gift_shares, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :sold_after_granted

  before_validation :default_sell_on

  delegate :price, :currency, to: :stock_plan

  # The bonus before taxes.
  def gross_bonus
    stock_plan.base_bonus.to_d * achievement_percent.to_d / 100
  end

  # The part of the bonus taken in shares (no income tax on it).
  def stock_amount
    gross_bonus * stock_percent.to_d / 100
  end

  # The cash paid into the account: the rest, after the income tax withheld.
  def net_cash
    ((gross_bonus - stock_amount) * (1 - stock_plan.tax_percent.to_d / 100)).round(2)
  end

  def delivered?(today: Date.current)
    granted_on <= today
  end

  # :typed, :traded or :estimated (see the class comment); nil when they
  # cannot be worked out (no price yet).
  def shares_source(today: Date.current)
    return :typed if shares.present?
    return :traded if delivered?(today: today) && traded_shares.positive?

    :estimated if estimated_bought
  end

  # Shares bought, without the free ones (nil when only the total is known
  # from the trades, or nothing can be worked out).
  def bought_shares(today: Date.current)
    case shares_source(today: today)
    when :typed then shares.to_d
    when :estimated then estimated_bought
    end
  end

  def free_shares(today: Date.current)
    return gift_shares.to_d if gift_shares.present?

    bought = bought_shares(today: today)
    return 0 if bought.nil? || stock_plan.gift_every.to_i.zero?

    (bought / stock_plan.gift_every).floor
  end

  def total_shares(today: Date.current)
    case shares_source(today: today)
    when :traded then traded_shares
    when nil then nil
    else bought_shares(today: today) + free_shares(today: today)
    end
  end

  # What the shares are worth at the latest price.
  def value(today: Date.current)
    total = total_shares(today: today)
    return nil if total.nil? || price.nil?

    (total * price).round(2)
  end

  private
    def estimated_bought
      return nil if price.nil? || !price.positive?

      (stock_amount / price).floor
    end

    def traded_shares
      @traded_shares ||= stock_plan.traded_shares_around(granted_on)
    end

    def default_sell_on
      return if granted_on.blank? || sell_on.present? || stock_plan.nil?

      self.sell_on = granted_on + stock_plan.lock_years.to_i.years
    end

    def sold_after_granted
      errors.add(:sell_on, :before_granted) if granted_on && sell_on && sell_on < granted_on
    end
end
