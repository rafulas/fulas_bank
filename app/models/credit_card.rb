class CreditCard < ApplicationRecord
  include Accountable

  DEFAULT_SUBTYPE = "credit_card"

  # Fulas Bank: the account the monthly statement is charged to, and the
  # statement's closing and payment days (see CreditCard::Cycle).
  belongs_to :payment_account, class_name: "Account", optional: true

  validates :statement_closing_day, :payment_day, numericality: { only_integer: true, in: 1..31 }, allow_nil: true
  validates :consolidation_days, numericality: { only_integer: true, in: 0..10 }
  validate :payment_account_in_the_family

  def statement_cycle
    CreditCard::Cycle.new(account)
  end

  SUBTYPES = {
    "credit_card" => { short: "Credit Card", long: "Credit Card" }
  }.freeze

  class << self
    def color
      "#F13636"
    end

    def icon
      "credit-card"
    end

    def classification
      "liability"
    end
  end

  def available_credit_money
    available_credit ? Money.new(available_credit, account.currency) : nil
  end

  def minimum_payment_money
    minimum_payment ? Money.new(minimum_payment, account.currency) : nil
  end

  def annual_fee_money
    annual_fee ? Money.new(annual_fee, account.currency) : nil
  end

  private
    def payment_account_in_the_family
      return if payment_account.nil?
      return if account.nil? || (payment_account.family_id == account.family_id && payment_account.accountable_type == "Depository")

      errors.add(:payment_account, :invalid)
    end
end
