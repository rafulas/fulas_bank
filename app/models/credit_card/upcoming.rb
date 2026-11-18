# Fulas Bank: what a card will charge next, for «Próximos extractos» in
# Inicio (see Transaction::Panel):
#   - the statement already closed and not charged yet, if any;
#   - the statement still open, with what it has so far;
#   - the instalments of purchases paid in instalments charged with it (the
#     bank charges them apart, «Operación financiada con tarjeta», on the
#     same day or a day or two after), and what is still deferred.
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

  # The fees and instalments still to come in the month the next statement
  # is charged, whatever their day (the 4th, 5th or 6th), or, without a
  # statement, in the month of the next one.
  def installments
    @installments ||= begin
      upcoming = overview.active_financings
                         .flat_map { |financing| financing.charges(cycle) }
                         .select { |charge| charge.date > today }
      month = next_charge&.charged_on || upcoming.map(&:date).min
      month ? upcoming.select { |charge| charge.date.beginning_of_month == month.beginning_of_month }.sort_by(&:date) : []
    end
  end

  def installments_amount
    installments.sum(&:amount).to_d
  end

  def installment_dates
    installments.map(&:date).uniq
  end

  # What will be charged: the next statement plus those instalments.
  def total_amount
    next_charge&.amount.to_d + installments_amount
  end

  def total_money
    Money.new(total_amount, account.currency)
  end

  def total_amount_in(currency)
    money = total_money
    money.currency.iso_code == currency.to_s ? money.amount.to_d : money.exchange_to(currency).amount.to_d
  rescue Money::ConversionError
    total_amount
  end

  # What is still to be charged of the purchases paid in instalments.
  def pending_financed
    overview.pending_financed
  end

  def financings_count
    overview.active_financings.size
  end

  private
    def overview
      @overview ||= CreditCard::Overview.new(account, cycle: cycle, today: today)
    end
end
