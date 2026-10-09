# The expected balance of each everyday account (current accounts and credit
# cards) on every day from tomorrow up to a chosen date, and of all of them
# together.
#
# It starts from today's balances and adds, day by day:
#   1. The recurring movements (salary, bills, mortgage, subscriptions...):
#      their pending payments already scheduled, and beyond those, as many as
#      their schedule produces up to the date, however far it is.
#   2. The one-off movements the user typed in (ForecastItem).
#   3. Optionally, the everyday variable spending (supermarket, fuel...): the
#      monthly average of the last three full months (or of the months with
#      movements, for a younger history) of movements that are not recurring,
#      not transfers and not one-off, spread evenly over the days, so the
#      forecast is not too optimistic.
#
# Amounts use the bank's convention, like entries: positive when money goes
# out of the account. An asset account loses it; a credit card owes it.
class Forecast
  ACCOUNT_TYPES = %w[Depository CreditCard].freeze
  VARIABLE_MONTHS = 3

  # Above this many days the chart gets one point a week instead of one a day.
  DAILY_POINTS_LIMIT = 731

  Flow = Data.define(:date, :account, :amount, :name, :source) do
    def inflow?
      amount.negative?
    end
  end

  attr_reader :family, :accounts, :through, :include_variable, :today

  def initialize(family, accounts:, through:, include_variable: true, today: Date.current)
    @family = family
    @accounts = accounts.select { |account| ACCOUNT_TYPES.include?(account.accountable_type) }
    @through = [ through, today + 1 ].max
    @include_variable = include_variable
    @today = today
  end

  def currency
    family.currency
  end

  # The recurring and one-off movements expected, by date. The variable
  # spending is not listed here, as it is spread over every day; see
  # #variable_monthly.
  def flows
    @flows ||= (recurring_flows + planned_flows).sort_by { |flow| [ flow.date, flow.name.to_s ] }
  end

  # What each account is expected to spend (positive) or receive (negative) in
  # a month outside its recurring movements.
  def variable_monthly
    @variable_monthly ||= include_variable ? compute_variable_monthly : {}
  end

  def variable_monthly_total
    money(variable_monthly.sum { |account, amount| to_family_currency(amount, account) })
  end

  # { account => balance } on `date` (a Money in the account's currency).
  def balances_on(date)
    date = date.clamp(today, through)
    accounts.index_with { |account| Money.new(balance_of(account, date), account.currency) }
  end

  # All the accounts together, in the family's currency: what is in the
  # current accounts minus what is owed on the cards.
  def total_on(date)
    date = date.clamp(today, through)
    money(accounts.sum { |account| net_worth_amount(account, balance_of(account, date)) } + unassigned_until(date))
  end

  # The lowest expected total and when, to warn before money runs short.
  def lowest_total
    dates.map { |date| [ date, total_on(date) ] }.min_by { |_, amount| amount.amount }
  end

  # A Series for the chart: the total, or one account's balance.
  def series(account: nil)
    values = dates.map do |date|
      value = account ? Money.new(balance_of(account, date), account.currency) : total_on(date)
      { date: date, value: value }
    end

    Series.from_raw_values(values, interval: weekly? ? "1 week" : "1 day")
  end

  private
    def money(amount)
      Money.new(amount, currency)
    end

    def weekly?
      (through - today).to_i > DAILY_POINTS_LIMIT
    end

    def dates
      @dates ||= begin
        step = weekly? ? 7 : 1
        list = today.step(through, step).to_a
        list << through unless list.last == through
        list
      end
    end

    # Balance of an account at the end of `date`, in its own currency and its
    # own sign (a credit card's balance is what it owes).
    def balance_of(account, date)
      running = running_balances[account.id]
      index = running[:dates].bsearch_index { |day| day > date } || running[:dates].size
      index.zero? ? running[:start] : running[:balances][index - 1]
    end

    # For each account, its balance after each day that has a flow, so any
    # date can be answered with a binary search.
    def running_balances
      @running_balances ||= accounts.to_h do |account|
        balance = account.balance.to_d
        deltas = daily_deltas[account.id] || {}
        days = deltas.keys.sort
        balances = days.map { |day| balance += sign_for(account) * deltas[day] }
        [ account.id, { start: account.balance.to_d, dates: days, balances: balances } ]
      end
    end

    # An asset account goes down when money goes out; a card's debt goes up.
    def sign_for(account)
      account.liability? ? 1 : -1
    end

    def net_worth_amount(account, balance)
      amount = to_family_currency(balance, account)
      account.liability? ? -amount : amount
    end

    # { account_id => { date => amount out } } for flows and variable spending.
    def daily_deltas
      @daily_deltas ||= begin
        deltas = Hash.new { |hash, key| hash[key] = Hash.new(0) }

        flows.each { |flow| deltas[flow.account.id][flow.date] += flow.amount if flow.account }

        variable_monthly.each do |account, monthly|
          ((today + 1)..through).each do |day|
            deltas[account.id][day] += monthly / Time.days_in_month(day.month, day.year)
          end
        end

        deltas
      end
    end

    # Recurring movements with no account (a series detected across several
    # accounts) still count in the total, as money going out of "somewhere".
    def unassigned_until(date)
      -flows.select { |flow| flow.account.nil? && flow.date <= date }.sum { |flow| flow.amount }
    end

    def to_family_currency(amount, account)
      return amount if account.currency == currency

      Money.new(amount, account.currency).exchange_to(currency).amount
    rescue Money::ConversionError
      amount
    end

    def account_ids
      @account_ids ||= accounts.map(&:id)
    end

    def accounts_by_id
      @accounts_by_id ||= accounts.index_by(&:id)
    end

    def window
      (today + 1)..through
    end

    # ---- 1. Recurring movements ----

    def recurring_flows
      series_list = family.recurring_transactions.active.includes(:recurrence_rules).select do |series|
        series.account_id.nil? || account_ids.include?(series.account_id) || account_ids.include?(series.destination_account_id)
      end

      series_list.flat_map { |series| flows_for_series(series) }
    end

    # Pending payments already scheduled (with any amount or date the user
    # changed), then whatever the schedule produces beyond them.
    def flows_for_series(series)
      stored = series.recurring_occurrences.to_a
      covered_until = stored.map(&:original_due_on).max || today

      scheduled = stored.select { |occurrence| occurrence.status == "scheduled" && window.cover?(occurrence.effective_due_on) }
                        .map { |occurrence| [ occurrence.effective_due_on, occurrence.remaining_amount ] }
                        .reject { |_, amount| amount.to_d.zero? }

      projected = series.schedule.occurrence_pairs_between(covered_until + 1, through)
                        .select { |pair| pair.original_due_on > covered_until && window.cover?(pair.due_on) }
                        .map { |pair| [ pair.due_on, projected_amount(series) ] }

      (scheduled + projected).flat_map { |date, amount| series_flows(series, date, amount.to_d.abs) }
    end

    def projected_amount(series)
      amount = series.amount_average? && series.expected_amount_avg.present? ? series.expected_amount_avg : series.amount
      amount.to_d.abs
    end

    # A bill takes money out of its account and a salary brings it in; a
    # recurring transfer does both, out of one account and into the other.
    def series_flows(series, date, amount)
      outflow = series.amount.to_d.positive? || series.destination_account_id.present?
      name = series.display_name
      source_account = accounts_by_id[series.account_id]
      list = []

      if series.account_id.nil? || source_account
        list << Flow.new(date: date, account: source_account, amount: outflow ? amount : -amount, name: name, source: :recurring)
      end

      if (destination = accounts_by_id[series.destination_account_id])
        list << Flow.new(date: date, account: destination, amount: -amount, name: name, source: :recurring)
      end

      list
    end

    # ---- 2. One-off movements typed by the user ----

    def planned_flows
      family.forecast_items.where(account_id: account_ids, date: window).map do |item|
        Flow.new(date: item.date, account: accounts_by_id[item.account_id], amount: item.signed_amount, name: item.name, source: :planned)
      end
    end

    # ---- 3. Everyday variable spending ----

    def compute_variable_monthly
      from = (today << VARIABLE_MONTHS).beginning_of_month
      to = (today << 1).end_of_month

      totals = family.entries
                     .where(account_id: account_ids, entryable_type: "Transaction", excluded: false, date: from..to)
                     .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
                     .where.not(transactions: { kind: Transaction::TRANSFER_KINDS + [ "one_time" ] })
                     .where("transactions.category_id IS NULL OR transactions.category_id NOT IN (#{Category::ANALYTICS_NEUTRAL_IDS_SQL})")
                     .where.not(transactions: { id: Transfer.select(:inflow_transaction_id) })
                     .where.not(transactions: { id: Transfer.select(:outflow_transaction_id) })
                     .where.not(id: RecurringAllocation.where.not(entry_id: nil).select(:entry_id))
                     .group(:account_id, Arel.sql("date_trunc('month', entries.date)"))
                     .sum(:amount)

      # Averaged over the months that have movements, so an account (or a
      # history) younger than three months is not diluted by empty months.
      totals.group_by { |(account_id, _month), _| account_id }.filter_map do |account_id, months|
        account = accounts_by_id[account_id]
        total = months.sum { |_, amount| amount.to_d }
        [ account, (total / months.size).round(2) ] if account && !total.zero?
      end.to_h
    end
end
