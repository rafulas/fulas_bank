# Fulas Bank: what a card will charge next, for «Próximos extractos» in
# Inicio (see Transaction::Panel):
#   - the statement already closed and not charged yet, if any;
#   - the statement still open, with what it has so far;
#   - the next instalment of a purchase paid in instalments.
# A card without its statement days set has no statements to show.
class CreditCard::Upcoming
  attr_reader :account, :cycle, :today

  def initialize(account, today: Date.current)
    @account = account
    @today = today
    @cycle = CreditCard::Cycle.new(account, today: today)
  end

  def configured?
    cycle.configured?
  end

  # The closed statement still waiting to be charged.
  def pending
    return @pending if defined?(@pending)

    statement = configured? ? cycle.last_closed : nil
    @pending = statement if statement && !statement.charged?(today) && statement.amount.positive?
  end

  # The statement open today.
  def current
    return @current if defined?(@current)

    @current = configured? ? cycle.current : nil
  end

  # The next one to be charged: the closed one waiting, else the open one.
  def next_charge
    pending || current
  end

  def next_charge_amount_in(currency)
    statement = next_charge
    return 0.to_d unless statement

    money = statement.amount_money
    money.currency.iso_code == currency.to_s ? money.amount.to_d : money.exchange_to(currency).amount.to_d
  rescue Money::ConversionError
    statement.amount.to_d
  end

  # [date, amount] of the next instalment of a purchase paid in instalments.
  def next_installment
    return @next_installment if defined?(@next_installment)

    @next_installment = CreditCard::Overview.new(account, cycle: cycle, today: today).next_installment
  end
end
