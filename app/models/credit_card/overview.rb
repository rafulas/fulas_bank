# Fulas Bank: the summary at the top of a credit card's statements tab,
# besides the open and the last statement (CreditCard::Cycle):
#   - how much of the limit is used: what is owed against the limit set on
#     the card ("Crédito disponible"), and what is left;
#   - the purchases paid in instalments (CardFinancing): what is still to be
#     charged, the next instalment, and what deferring cost this year (fees
#     and interest), plus the card's annual fee.
class CreditCard::Overview
  attr_reader :account, :cycle, :today

  def initialize(account, cycle:, today: cycle.today)
    @account = account
    @cycle = cycle
    @today = today
  end

  def card
    account.accountable
  end

  def currency
    account.currency
  end

  # ---- Limit ----

  def limit
    card.available_credit&.to_d
  end

  def limit?
    limit.present? && limit.positive?
  end

  # What is owed now (the card's balance), never below zero.
  def owed
    [ account.balance.to_d, 0.to_d ].max
  end

  def available
    [ limit - owed, 0.to_d ].max if limit?
  end

  # The share of the limit used, 0-100.
  def usage
    return unless limit?

    [ (owed / limit * 100).round, 100 ].min
  end

  # ---- Purchases paid in instalments ----

  def financings
    @financings ||= account.card_financings.includes(entry: :entryable).to_a
  end

  def active_financings
    @active_financings ||= financings.reject { |financing| financing.finished?(today: today, cycle: cycle) }
  end

  def pending_financed
    active_financings.sum { |financing| financing.pending_amount(today: today, cycle: cycle) }.to_d
  end

  # The next instalment of any of them: [date, amount].
  def next_installment
    charges = active_financings.filter_map { |financing| financing.next_charge(today: today, cycle: cycle) }
    return if charges.empty?

    date = charges.map(&:date).min
    [ date, charges.select { |charge| charge.date == date }.sum(&:amount).to_d ]
  end

  # Fees and interest of the purchases deferred this year.
  def financing_cost_this_year
    financings.select { |financing| financing.purchase_date.year == today.year }
              .sum { |financing| [ financing.cost(cycle: cycle), 0 ].max }.to_d
  end

  def annual_fee
    card.annual_fee&.to_d if card.annual_fee.to_d.positive?
  end

  def financing?
    active_financings.any? || financing_cost_this_year.positive?
  end
end
