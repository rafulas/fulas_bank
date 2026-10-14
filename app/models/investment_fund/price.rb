# Fulas Bank: one valor liquidativo of a fund on a date.
class InvestmentFund::Price < ApplicationRecord
  self.table_name = "investment_fund_prices"

  belongs_to :investment_fund

  validates :date, presence: true, uniqueness: { scope: :investment_fund_id }
  validates :price, numericality: { greater_than: 0 }
end
