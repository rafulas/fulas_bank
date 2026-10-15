# Fulas Bank: a credit card's monthly statement, as the bank works it out.
#
# The card closes on a day of the month (31: the last day, whatever the
# month) and the total is charged on a later day, in the account the card is
# paid from. Both are set on the card.
#
# - Which statement a purchase goes to: the one whose closing day is on or
#   after the day the bank books it. A purchase on a weekend or holiday is
#   booked the next working day, and the bank may take some working days more
#   ("consolidation_days"): a purchase on Saturday the 30th, or on Thursday
#   the 28th with two days of consolidation, goes to next month's statement.
#   A movement can also be sent to the next statement by hand.
# - When it is charged: the payment day of the month after it closes, or the
#   working day before when that day is a weekend or holiday (a 5th falling
#   on a Sunday is charged on Friday the 3rd).
# - What is charged: the purchases minus refunds of the statement, minus the
#   purchases paid in instalments (CardFinancing), which the bank charges
#   apart, with their fee and instalments.
#
# Working days follow SpanishHolidays (national and Madrid holidays).
class CreditCard::Cycle
  Statement = Data.define(:closes_on, :opens_on, :charged_on, :entries, :financed, :currency) do
    def month
      closes_on.beginning_of_month
    end

    def purchases
      entries.sum(&:amount).to_d
    end

    # What the bank will charge for it in the payment account.
    def amount
      [ purchases - financed, 0 ].max
    end

    def amount_money
      Money.new(amount, currency)
    end

    def purchases_money
      Money.new(purchases, currency)
    end

    def financed_money
      Money.new(financed, currency)
    end

    def open?(today = Date.current)
      today <= closes_on
    end

    def charged?(today = Date.current)
      charged_on <= today
    end
  end

  attr_reader :card, :account, :today

  def initialize(account, today: Date.current)
    @account = account
    @card = account.accountable
    @today = today
  end

  def configured?
    card.statement_closing_day.present? && card.payment_day.present?
  end

  def closing_date(month)
    month = month.beginning_of_month
    month.change(day: [ card.statement_closing_day, month.end_of_month.day ].min)
  end

  # The day the statement closing in `month` is charged.
  def charge_date(month)
    following = month.beginning_of_month.next_month
    day = following.change(day: [ card.payment_day, following.end_of_month.day ].min)
    SpanishHolidays.previous_business_day(day)
  end

  # The day the bank books a purchase made on `date`.
  def booking_date(date)
    SpanishHolidays.add_business_days(date, card.consolidation_days.to_i)
  end

  # The first day of the month whose statement a movement goes to.
  def statement_month_for(date, next_statement: false)
    booked = booking_date(date)
    month = booked.beginning_of_month
    month = month.next_month if booked > closing_date(month)
    next_statement ? month.next_month : month
  end

  def statement(month)
    statements_between(month, month).first
  end

  # The statement still open today (its purchases so far).
  def current
    statement(statement_month_for(today))
  end

  # The last statement already closed (charged or about to be).
  def last_closed
    statement(statement_month_for(today).prev_month)
  end

  # The statements closing from `from_month` to `to_month`, oldest first.
  def statements_between(from_month, to_month)
    return [] unless configured?

    months = []
    month = from_month.beginning_of_month
    while month <= to_month.beginning_of_month
      months << month
      month = month.next_month
    end

    grouped = movements_for(months).group_by do |entry|
      statement_month_for(entry.date, next_statement: entry.entryable.next_card_statement)
    end
    financed = financed_by_month(months)

    months.map do |each_month|
      Statement.new(
        closes_on: closing_date(each_month),
        opens_on: closing_date(each_month.prev_month) + 1,
        charged_on: charge_date(each_month),
        entries: grouped.fetch(each_month, []).sort_by(&:date),
        financed: financed.fetch(each_month, 0).to_d,
        currency: account.currency
      )
    end
  end

  # The last `count` statements, newest first, starting from the open one.
  def recent(count = 6)
    to_month = statement_month_for(today)
    statements_between(to_month << (count - 1), to_month).reverse
  end

  private
    # The card's purchases and refunds that can fall in those statements:
    # transfers in or out of the card (paying it off) are not purchases.
    def movements_for(months)
      from = closing_date(months.first.prev_month) - 20
      to = closing_date(months.last) + 1

      account.entries.where(entryable_type: "Transaction", date: from..to)
             .excluding_split_parents
             .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
             .where.not(transactions: { kind: Transaction::TRANSFER_KINDS })
             .where.not(transactions: { id: Transfer.select(:inflow_transaction_id) })
             .where.not(transactions: { id: Transfer.select(:outflow_transaction_id) })
             .includes(:entryable)
             .to_a
             .select { |entry| months.include?(statement_month_for(entry.date, next_statement: entry.entryable.next_card_statement)) }
    end

    def financed_by_month(months)
      CardFinancing.where(account_id: account.id).includes(entry: :entryable).each_with_object(Hash.new(0)) do |financing, totals|
        month = financing.statement_month(self)
        totals[month] += financing.financed_amount.to_d if months.include?(month)
      end
    end
end
