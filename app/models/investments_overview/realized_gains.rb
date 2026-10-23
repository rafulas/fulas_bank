# Fulas Bank: what the year's sales of shares gained or lost, sale by sale,
# worked out two ways from the account's own trades:
#   - average cost: each sale's shares cost the average of what is held
#     (what the rest of the app shows);
#   - FIFO: the first shares bought are the first sold, the method the
#     Spanish tax return («renta») requires.
# With a single purchase both agree; with several at different prices they
# do not, and the tax figure is the FIFO one.
#
# Shares received as pay (Trade::CreateForm's "grant") are a buy at the value
# received, so their gain counts from that value. Fees add to a buy's cost
# and come off a sale's proceeds. Amounts are in each trade's currency,
# totals in the family's.
class InvestmentsOverview::RealizedGains
  Sale = Data.define(:date, :account, :security, :qty, :proceeds, :average_gain, :fifo_gain, :currency)

  attr_reader :family, :user, :year

  def initialize(family, user:, year: nil, today: Date.current)
    @family = family
    @user = user
    @today = today
    @year = (year.presence || today.year).to_i
  end

  def sales
    @sales ||= all_sales.select { |sale| sale.date.year == year }
  end

  def any?
    sales.any?
  end

  def years
    @years ||= (all_sales.map { |sale| sale.date.year } + [ @today.year ]).uniq.sort.reverse
  end

  def average_total
    total(:average_gain)
  end

  def fifo_total
    total(:fifo_gain)
  end

  private
    def total(attribute)
      Money.new(sales.sum { |sale| converted(sale.public_send(attribute), sale.currency) }, family.currency)
    end

    def all_sales
      @all_sales ||= trades.group_by { |entry| [ entry.account_id, entry.entryable.security_id ] }
                           .flat_map { |_, list| sales_of(list) }
                           .sort_by(&:date)
    end

    # One position's trades in date order: buys stack up lots, sales use
    # them up.
    def sales_of(entries)
      lots = []
      held = 0.to_d
      cost = 0.to_d

      entries.filter_map do |entry|
        trade = entry.entryable
        qty = trade.qty.to_d
        price = trade.price.to_d
        fee = trade.fee.to_d

        if qty.positive?
          lots << [ qty, (qty * price + fee) / qty ]
          held += qty
          cost += qty * price + fee
          next
        end

        sold = qty.abs
        next if sold.zero? || held.zero?

        proceeds = sold * price - fee
        average_cost = cost / held * [ sold, held ].min
        fifo_cost = take_fifo(lots, sold)
        cost -= average_cost
        held -= [ sold, held ].min

        Sale.new(date: entry.date, account: entry.account, security: trade.security, qty: sold,
                 proceeds: proceeds, average_gain: proceeds - average_cost, fifo_gain: proceeds - fifo_cost,
                 currency: entry.currency)
      end
    end

    # What the first lots still held cost for `sold` shares, using them up.
    def take_fifo(lots, sold)
      remaining = sold
      cost = 0.to_d
      while remaining.positive? && lots.any?
        lot_qty, unit_cost = lots.first
        used = [ lot_qty, remaining ].min
        cost += used * unit_cost
        remaining -= used
        lot_qty == used ? lots.shift : lots[0] = [ lot_qty - used, unit_cost ]
      end
      cost
    end

    def trades
      account_ids = family.accounts.accessible_by(user).where(accountable_type: InvestmentsOverview::ACCOUNT_TYPES).pluck(:id)
      Entry.where(account_id: account_ids, entryable_type: "Trade", excluded: false)
           .includes(:account, entryable: :security)
           .order(:date, :created_at)
           .to_a
    end

    def converted(amount, from_currency)
      return amount.to_d if from_currency == family.currency

      Money.new(amount, from_currency).exchange_to(family.currency).amount
    rescue Money::ConversionError
      amount.to_d
    end
end
