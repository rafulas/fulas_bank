# Fulas Bank: a credit card purchase paid in instalments ("pago financiado"),
# with the figures the bank's app shows when it is financed.
#
# The bank takes it out of the monthly statement it falls in and charges it
# apart, in the account the card is paid from:
#   - on that statement's charge day, the fee ("comisión"), and
#   - on each of the next `installments_count` charge days, one instalment.
# For example, a 345,67 € purchase in September financed at 9 months: the 5th
# of October, the statement without it plus the fee; from the 5th of
# November to the 5th of July, one instalment each.
#
# The purchase still counts as spending in its month. The instalments repay
# the card (a transfer from the account to the card) and only the fee and
# the interest in the instalments are a cost.
class CardFinancing < ApplicationRecord
  include Monetizable

  belongs_to :family
  belongs_to :account
  belongs_to :entry, optional: true

  monetize :financed_amount, :installment_amount, :fee_amount

  validates :name, :purchase_date, :currency, presence: true
  validates :financed_amount, :installment_amount, numericality: { greater_than: 0 }
  validates :fee_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :installments_count, numericality: { only_integer: true, in: 1..120 }
  validate :account_is_a_credit_card

  # One charge in the payment account: the fee or an instalment.
  Charge = Data.define(:date, :amount, :kind, :number)

  def self.from_entry(entry)
    new(family: entry.account.family, account: entry.account, entry: entry, name: entry.name,
        purchase_date: entry.date, financed_amount: entry.amount.abs, currency: entry.currency)
  end

  # The statement the purchase falls in (first day of its month).
  def statement_month(cycle = cycle_for)
    cycle.statement_month_for(purchase_date, next_statement: entry&.entryable&.try(:next_card_statement))
  end

  # The fee, then each instalment, with the day it is charged.
  def charges(cycle = cycle_for)
    return [] unless cycle.configured?

    month = statement_month(cycle)
    list = []
    list << Charge.new(date: cycle.charge_date(month), amount: fee_amount.to_d, kind: :fee, number: 0) if fee_amount.to_d.positive?
    installments_count.times do |index|
      list << Charge.new(date: cycle.charge_date(month >> (index + 1)), amount: installment_amount.to_d, kind: :installment, number: index + 1)
    end
    list
  end

  # Fulas Bank: each charge with whether its day has passed and the bank's
  # «Operación financiada» charge that day, if imported (see
  # CreditCard::Reconciler#financed_charge_on). That bank charge may also pay
  # other financed purchases due the same day.
  ChargeLine = Data.define(:charge, :paid, :bank_entry)

  def charge_lines(today: Date.current, cycle: cycle_for, reconciler: CreditCard::Reconciler.new(account, today: today))
    charges(cycle).map do |charge|
      paid = charge.date <= today
      ChargeLine.new(charge: charge, paid: paid, bank_entry: paid ? reconciler.financed_charge_on(charge.date) : nil)
    end
  end

  def total_to_pay
    installment_amount.to_d * installments_count + fee_amount.to_d
  end

  # What it costs on top of the purchase (fee and interest).
  def cost
    total_to_pay - financed_amount.to_d
  end

  # The instalments do not even repay the purchase: the figures were likely
  # typed wrong.
  def mismatch?
    installment_amount.to_d * installments_count < financed_amount.to_d - 0.01
  end

  def paid_installments(today: Date.current, cycle: cycle_for)
    charges(cycle).count { |charge| charge.kind == :installment && charge.date <= today }
  end

  def pending_amount(today: Date.current, cycle: cycle_for)
    charges(cycle).reject { |charge| charge.date <= today }.sum(&:amount)
  end

  def next_charge(today: Date.current, cycle: cycle_for)
    charges(cycle).find { |charge| charge.date > today }
  end

  def finished?(today: Date.current, cycle: cycle_for)
    next_charge(today: today, cycle: cycle).nil?
  end

  def cycle_for
    CreditCard::Cycle.new(account)
  end

  private
    def account_is_a_credit_card
      errors.add(:account, :invalid) unless account&.accountable_type == "CreditCard"
    end
end
