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
# When the bank does not follow the card's charge day, the fee and the first
# instalment can be given their own day (`fee_on`, `first_installment_on`);
# the instalments then fall on that day of each month.
#
# Paid off early (`paid_off_on`): that day the bank charges what was left
# (`payoff_amount`, or the instalments still due if not given) and the
# instalments after it are not charged. In the example, paying off the 5th of
# March after February's instalment: 50 € that day and no April instalment.
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
  validates :payoff_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :fee_on, :first_installment_on, :paid_off_on, comparison: { greater_than_or_equal_to: :purchase_date }, allow_nil: true
  validate :account_is_a_credit_card
  before_save -> { self.payoff_amount = nil }, unless: :paid_off_on?

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

  # The fee, then each instalment, with the day it is charged. Paid off
  # early, the instalments from that day on give way to one :payoff charge.
  def charges(cycle = cycle_for)
    planned = planned_charges(cycle)
    return planned unless paid_off_on

    kept = planned.select { |charge| charge.date < paid_off_on }
    due = planned.select { |charge| charge.kind == :installment && charge.date >= paid_off_on }
    amount = payoff_amount.nil? ? due.sum(&:amount) : payoff_amount.to_d
    number = due.first&.number || installments_count
    kept << Charge.new(date: paid_off_on, amount: amount, kind: :payoff, number: number) if amount.positive?
    kept
  end

  # The charges as financed, before any early payoff.
  def planned_charges(cycle = cycle_for)
    return [] unless cycle.configured? || first_installment_on

    month = cycle.configured? ? statement_month(cycle) : nil
    list = []
    fee_date = fee_on || (month ? cycle.charge_date(month) : first_installment_on)
    list << Charge.new(date: fee_date, amount: fee_amount.to_d, kind: :fee, number: 0) if fee_amount.to_d.positive?
    installments_count.times do |index|
      date = first_installment_on ? first_installment_on >> index : cycle.charge_date(month >> (index + 1))
      list << Charge.new(date: date, amount: installment_amount.to_d, kind: :installment, number: index + 1)
    end
    list
  end

  # What was still due on `date` (the instalments from that day on), to
  # suggest it when paying off early.
  def due_on(date, cycle: cycle_for)
    planned_charges(cycle).select { |charge| charge.kind == :installment && charge.date >= date }.sum(&:amount)
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

  # What is paid in all: the fee and the instalments, or, paid off early, the
  # fee, the instalments before and what was paid off.
  def total_to_pay(cycle: cycle_for)
    list = paid_off_on ? charges(cycle) : []
    return list.sum(&:amount) if list.any?

    installment_amount.to_d * installments_count + fee_amount.to_d
  end

  # What it costs on top of the purchase (fee and interest).
  def cost(cycle: cycle_for)
    total_to_pay(cycle: cycle) - financed_amount.to_d
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
