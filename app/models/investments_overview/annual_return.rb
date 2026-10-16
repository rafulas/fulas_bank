# Fulas Bank: the yearly return of an investment account, or of all of them
# together, taking into account when each euro went in (the internal rate of
# return, TIR in Spanish, solved by Portfolio::Xirr).
#
# Each account's money movements are flows from the investor's side:
#   - money put in is money the investor gave (negative);
#   - money taken out is money the investor got (positive);
#   - and today the investor "gets" what the account is worth.
# An account started with a balance (not built from contributions) counts
# what it was worth on its first day of history as put in that day. An account recorded only
# purchase by purchase, with no money movements, counts each purchase as
# money put in that day.
#
# Accounts with no flows to measure (a fund whose value is typed by hand and
# nothing else) are left out, and so are those that cannot be solved (money
# only went one way, or everything on one day): #measured tells which counted.
#
# A return is only given as yearly once there is at least a year of history,
# as banks and fund managers do: 380 % gained in six days, "annualised", is a
# number with dozens of digits that says nothing. Until then #young? is true
# and the page shows the plain return instead.
class InvestmentsOverview::AnnualReturn
  MIN_DAYS = 365

  attr_reader :accounts, :currency, :today

  # @param accounts [Array<Account>] investment and crypto accounts
  # @param currency [String] the currency to add accounts up in
  def initialize(accounts, currency:, today: Date.current)
    @accounts = accounts
    @currency = currency
    @today = today
  end

  # @return [Float, nil] the yearly rate (0.0785 is 7,85 %)
  def rate
    flows = with_flows.flat_map { |account| flows_for(account) }
    return if flows.size < 2 || short?(flows)

    Portfolio::Xirr.rate_or_nil(flows)&.to_f
  end

  # @return [Float, nil] one account's yearly rate
  def rate_for(account)
    flows = flows_for(account)
    return if flows.size < 2 || short?(flows)

    Portfolio::Xirr.rate_or_nil(flows)&.to_f
  end

  # The accounts with a rate of their own.
  def measured
    @measured ||= accounts.select { |account| rate_for(account) }
  end

  # Whether an account (or, without one, the whole portfolio) has money in it
  # but less than a year of history to give a yearly return.
  def young?(account = nil)
    flows = account ? flows_for(account) : with_flows.flat_map { |each| flows_for(each) }
    flows.size >= 2 && short?(flows)
  end

  private
    def with_flows
      accounts.select { |account| flows_for(account).size >= 2 }
    end

    def short?(flows)
      (today - flows.map(&:first).min).to_i < MIN_DAYS
    end

    # [[date, amount]] in `currency`, from the investor's side.
    def flows_for(account)
      @flows_for ||= {}
      @flows_for[account.id] ||= begin
        # Fulas Bank: an account without brokerage cash has no money
        # movements of its own: its buys and sales are the money in and out.
        moves = account.brokerage_cash? ? money_movements(account) : []
        moves = purchases(account) if moves.empty?
        list = opening(account, moves) + moves
        list << [ today, convert(account.balance.to_d, account) ] if list.any?
        list
      end
    end

    # Money into the account is negative in entries already: the investor's sign.
    def money_movements(account)
      account.entries.where(entryable_type: "Transaction", excluded: false, date: ..today)
             .excluding_split_parents.order(:date).pluck(:date, :amount)
             .map { |date, amount| [ date, convert(amount.to_d, account) ] }
    end

    # A buy is money the investor put in; a sale, money taken out.
    def purchases(account)
      account.entries.where(entryable_type: "Trade", excluded: false, date: ..today).order(:date).pluck(:date, :amount)
             .map { |date, amount| [ date, -convert(amount.to_d, account) ] }
    end

    # The value the account already had on its first day of history, before
    # that day's money movements (an account opened with a balance, or whose
    # value was typed in): counted as put in that day.
    def opening(account, moves)
      first = account.balances.where(currency: account.currency).order(:date).first
      return [] unless first

      same_day = moves.select { |date, _| date == first.date }.sum { |_, amount| amount }
      value = convert(first.end_balance.to_d, account) + same_day
      return [] unless value > 0.01

      [ [ first.date, -value ] ]
    end

    def convert(amount, account)
      return amount if account.currency == currency

      Money.new(amount, account.currency).exchange_to(currency).amount
    rescue Money::ConversionError
      amount
    end
end
