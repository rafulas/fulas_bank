# The expected balance of each everyday account (current accounts and credit
# cards) on every day from tomorrow up to a chosen date, and of all of them
# together, and the table of every expected movement behind it.
#
# It starts from today's balances and adds, line by line:
#   1. The recurring movements (salary, bills, mortgage, subscriptions...):
#      their pending payments already scheduled, and beyond those, as many as
#      their schedule produces up to the date, however far it is. A series
#      that ends (a loan, a plan with an end date) stops there.
#   2. The one-off movements the user typed in (ForecastItem).
#   3. Optionally, one "Gastos varios" line a month per account with the
#      expected variable spending (see Forecast::VariableEstimate), on the last
#      day of the month. In the current month, only what is still to come.
#   4. When the debt plan feeds the forecast (DebtPlan::ForecastFeed), its
#      loan payments and one-off contributions, which replace the recurring
#      movements linked to the loans from next month on.
#   5. For a card with its statement days set (CreditCard::Cycle), what it
#      will charge for the purchases already made (the statement still open
#      and the last one if it has not been charged yet) on its payment day,
#      and the fees and instalments of its purchases paid in instalments
#      (CardFinancing), in the account it is paid from.
#   6. The instalments of the insurance policies paid in custom instalments
#      (Insurance#installment_charges_between), every year on the same days,
#      in the account they are charged to (a card's go to the main account).
#      Fulas Bank: a policy paid monthly, quarterly, twice or once a year
#      too, from its renewal day, unless a recurring movement already covers
#      it (one of about the same amount); and none after the day a policy
#      that will not be renewed ends.
#   7. Fulas Bank: the instalment of each loan (Préstamos), every month on
#      its payment day in the main account until it is paid off, unless a
#      recurring movement already pays it (towards the loan, or of about the
#      same amount) or the debt plan feeds the forecast.
#
# Fulas Bank: statements are imported by hand, days or weeks late. A payment
# of 1 or 6 whose day has passed but is later than the last movement imported
# for its account has not reached the balance yet, so it is still expected:
# it goes on tomorrow, named with the day it was due ("vencía el 19/10"). One
# on or before that last movement is taken as charged (OVERDUE_LOOKBACK caps
# how far back this looks).
#
# The user can change the date, amount or name of a line of 1, 3 and 6, or leave
# it out, from the table; those changes are ForecastAdjustments, applied here
# by the line's key. A line left out is still listed (so it can be brought
# back) but does not count.
#
# Credit cards are not shown: what is spent on them is paid from the main
# account in the end. So a recurring charge on a card is expected in the
# main account, a recurring payment of the card itself is left out (it would
# count that spending twice), and the variable spending on cards goes into
# the main account's "Gastos varios" line.
#
# Amounts use the bank's convention, like entries: positive when money goes
# out of the account. An asset account loses it.
class Forecast
  # Current and savings accounts and investments: the ones the forecast shows.
  ACCOUNT_TYPES = %w[Depository Investment Crypto].freeze
  CARD_TYPES = %w[CreditCard].freeze
  MAIN_ACCOUNT_PREFERENCE = "forecast_main_account_id".freeze
  # Fulas Bank: the least the main account should ever have ("colchón").
  CUSHION_PREFERENCE = "forecast_cushion".freeze
  # Fulas Bank: the table's columns, set from "Editar tabla": the accounts
  # hidden, and the group each account adds up in.
  HIDDEN_COLUMNS_PREFERENCE = "forecast_hidden_columns".freeze
  COLUMN_GROUPS_PREFERENCE = "forecast_column_groups".freeze

  # Fulas Bank: like the user's spreadsheet, the total is the cash (current
  # and savings accounts) plus the savings and investments (funds, shares).
  # An account can also be left out of the totals ("none"): it still has its
  # own column.
  GROUPS = %w[cash investment none].freeze

  # Fulas Bank: how far back a payment not imported yet is still expected.
  OVERDUE_LOOKBACK = 45.days

  # Fulas Bank: a recurring movement this close in amount to a loan
  # instalment or an insurance premium is taken as the one that pays it.
  SAME_AMOUNT_TOLERANCE = BigDecimal("0.03")

  # Above this many days the chart gets one point a week instead of one a day.
  DAILY_POINTS_LIMIT = 731

  # One expected movement. `key` identifies a line the app works out by itself
  # (recurring or variable) so the user's changes to it can be found again;
  # `record` is the ForecastItem behind a one-off line.
  Flow = Data.define(:date, :account, :amount, :name, :source, :key, :skipped, :adjusted, :record, :card) do
    def initialize(date:, account:, amount:, name:, source:, key: nil, skipped: false, adjusted: false, record: nil, card: nil)
      super
    end

    def inflow?
      amount.negative?
    end
  end

  # A line of the table with the balances right after it: each account's (in
  # its own currency and sign) and the total (in the family's currency).
  LedgerRow = Data.define(:flow, :balances, :total) do
    def month?
      false
    end
  end

  # The row opening a month in the table: the month's result (from the
  # user's side) and the balances it ends on.
  MonthRow = Data.define(:month, :net, :balances, :total) do
    def month?
      true
    end
  end

  attr_reader :family, :accounts, :card_accounts, :main_account, :through, :include_variable, :today, :debt_plan, :column_groups

  # `main_account` is where the monthly variable spending and the card
  # charges are expected (by default the first current account);
  # `card_accounts` are the cards whose spending ends up there.
  def initialize(family, accounts:, through:, include_variable: true, today: Date.current, main_account: nil, card_accounts: [], debt_plan: nil, column_groups: {})
    @family = family
    @accounts = accounts.select { |account| ACCOUNT_TYPES.include?(account.accountable_type) }
    @card_accounts = card_accounts.select { |account| CARD_TYPES.include?(account.accountable_type) }
    @main_account = @accounts.find { |account| account == main_account } || self.class.default_main_account(@accounts)
    @through = [ through, today + 1 ].max
    @include_variable = include_variable
    @today = today
    @debt_plan = debt_plan
    @column_groups = (column_groups || {}).to_h.transform_keys(&:to_s)
  end

  # Fulas Bank: "cash", "investment" or "none" (see GROUPS): what the user
  # chose in "Editar tabla", or by the kind of account.
  def group_for(account)
    chosen = column_groups[account.id.to_s]
    return chosen if GROUPS.include?(chosen)

    self.class.default_group(account)
  end

  def self.default_group(account)
    account.accountable_type == "Depository" ? "cash" : "investment"
  end

  # The accounts that add up in the totals.
  def counted_accounts
    @counted_accounts ||= accounts.reject { |account| group_for(account) == "none" }
  end

  # { "cash" => Money, "investment" => Money } for a row's balances, in the
  # family's currency.
  def group_totals(balances)
    %w[cash investment].index_with do |group|
      money(accounts.select { |account| group_for(account) == group }.sum { |account| net_worth_amount(account, balances[account.id]) })
    end
  end

  def self.default_main_account(accounts)
    accounts.find { |account| account.accountable_type == "Depository" } || accounts.first
  end

  def currency
    family.currency
  end

  # Every expected movement by date, including the lines the user left out
  # (with `skipped`), which do not count in any balance. On the same day, the
  # month's variable spending goes last.
  def flows
    @flows ||= (adjusted(recurring_flows + variable_flows + insurance_flows + policy_flows + loan_flows) + planned_flows + debt_plan_flows + card_flows)
                 .sort_by { |flow| [ flow.date, flow.source == :variable ? 1 : 0, flow.name.to_s ] }
  end

  def active_flows
    @active_flows ||= flows.reject(&:skipped)
  end

  # The table: every line with the balances right after it. With an account,
  # only that account's lines (the balances still cover every account).
  def ledger(account: nil)
    balances = accounts.to_h { |each_account| [ each_account.id, each_account.balance.to_d ] }
    unassigned = 0

    rows = flows.map do |flow|
      unless flow.skipped
        if flow.account
          balances[flow.account.id] += sign_for(flow.account) * flow.amount
        else
          unassigned -= flow.amount
        end
      end

      total = counted_accounts.sum { |each_account| net_worth_amount(each_account, balances[each_account.id]) } + unassigned
      LedgerRow.new(flow: flow, balances: balances.dup, total: money(total))
    end

    account ? rows.select { |row| row.flow.account == account } : rows
  end

  # The table's rows: each month's opening row, then its lines.
  def table_rows(ledger_rows)
    ledger_rows.group_by { |row| row.flow.date.beginning_of_month }.flat_map do |month, month_rows|
      net = month_rows.reject { |row| row.flow.skipped }.sum(money(0)) { |row| user_amount(row.flow) }
      last = month_rows.last
      [ MonthRow.new(month: month, net: net, balances: last.balances, total: last.total) ] + month_rows
    end
  end

  # A line's amount from the user's side, in the family's currency: income
  # positive, spending negative.
  def user_amount(flow)
    amount = flow.account ? to_family_currency(flow.amount, flow.account) : flow.amount
    money(-amount)
  end

  # { account => balance } on `date` (a Money in the account's currency).
  def balances_on(date)
    date = date.clamp(today, through)
    accounts.index_with { |account| Money.new(balance_of(account, date), account.currency) }
  end

  # The accounts that add up (see #group_for), in the family's currency: what is in the
  # current accounts minus what is owed on the cards.
  def total_on(date)
    date = date.clamp(today, through)
    money(counted_accounts.sum { |account| net_worth_amount(account, balance_of(account, date)) } + unassigned_until(date))
  end

  # The lowest expected total and when, to warn before money runs short. It
  # looks at every day with a line too, which the weekly chart may skip.
  def lowest_total
    checked_dates.map { |date| [ date, total_on(date) ] }.min_by { |_, amount| amount.amount }
  end

  # The first day `account` is expected to drop below `minimum` (in its own
  # currency), and its balance that day; nil when it never does. Like
  # #lowest_total, it looks at every day with a line.
  def first_below(account, minimum)
    return if account.nil? || minimum.nil?

    checked_dates.each do |date|
      balance = balance_of(account, date)
      return [ date, Money.new(balance, account.currency) ] if balance < minimum
    end

    nil
  end

  # The lowest expected balance of `account` and when.
  def lowest_balance(account)
    return if account.nil?

    date, balance = checked_dates.map { |day| [ day, balance_of(account, day) ] }.min_by { |_, amount| amount }
    [ date, Money.new(balance, account.currency) ]
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

    # The chart's days and every day with a line.
    def checked_dates
      @checked_dates ||= (dates | active_flows.map(&:date)).sort
    end

    # The chart's days: every day, or one a week for long horizons.
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

    # For each account, its balance after each day that has a line, so any
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

    # { account_id => { date => amount out } } for the lines that count.
    def daily_deltas
      @daily_deltas ||= begin
        deltas = Hash.new { |hash, key| hash[key] = Hash.new(0) }
        active_flows.each { |flow| deltas[flow.account.id][flow.date] += flow.amount if flow.account }
        deltas
      end
    end

    # Recurring movements with no account (a series detected across several
    # accounts) still count in the total, as money going out of "somewhere".
    def unassigned_until(date)
      -active_flows.select { |flow| flow.account.nil? && flow.date <= date }.sum { |flow| flow.amount }
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

    # Fulas Bank: the day a payment due on `date` is expected, or nil when it
    # is not: its own day inside the window, or tomorrow when it is overdue
    # but later than the last movement imported for `account_id` (so it has
    # not reached the balance yet). See the class comment.
    def expected_date(date, account_id)
      return date if window.cover?(date)
      return nil if date > through || date < today - OVERDUE_LOOKBACK

      last_imported = last_entry_dates[account_id]
      return nil if last_imported.nil? || date <= last_imported

      window.first
    end

    # { account_id => date of its newest movement up to today }.
    def last_entry_dates
      @last_entry_dates ||= family.entries.where(date: ..today).group(:account_id).maximum(:date)
    end

    def overdue_name(name, due_on, expected_on)
      return name if due_on == expected_on

      I18n.t("forecasts.overdue_line", name: name, date: I18n.l(due_on, format: "%d/%m"))
    end

    # ---- 1. Recurring movements ----

    def recurring_flows
      series_list = family.recurring_transactions.active.includes(:recurrence_rules).select do |series|
        next false if card_ids.include?(series.destination_account_id) # paying a card off

        series.account_id.nil? || account_ids.include?(series.account_id) ||
          card_ids.include?(series.account_id) || account_ids.include?(series.destination_account_id)
      end

      series_list.flat_map do |series|
        list = flows_for_series(series)
        # The debt plan pays this loan from the month it starts.
        debt_plan&.replaces?(series) ? list.select { |flow| flow.date < debt_plan.starts_on } : list
      end
    end

    # Pending payments already scheduled (with any amount or date the user
    # changed in Bills), then whatever the schedule produces beyond them.
    def flows_for_series(series)
      stored = series.recurring_occurrences.to_a
      covered_until = stored.map(&:original_due_on).max || today

      scheduled = stored.select { |occurrence| occurrence.status == "scheduled" }
                        .filter_map do |occurrence|
                          on = expected_date(occurrence.effective_due_on, series.account_id)
                          [ on, occurrence.remaining_amount, occurrence.original_due_on, occurrence.effective_due_on ] if on
                        end
                        .reject { |_, amount, _| amount.to_d.zero? }

      projected = series.schedule.occurrence_pairs_between(covered_until + 1, through)
                        .select { |pair| pair.original_due_on > covered_until && window.cover?(pair.due_on) }
                        .map { |pair| [ pair.due_on, projected_amount(series), pair.original_due_on, pair.due_on ] }

      (scheduled + projected).flat_map do |date, amount, original_date, due_on|
        series_flows(series, date, amount.to_d.abs, ForecastAdjustment.recurring_key(series, original_date),
                     name: overdue_name(series.display_name, due_on, date))
      end
    end

    def projected_amount(series)
      amount = series.amount_average? && series.expected_amount_avg.present? ? series.expected_amount_avg : series.amount
      amount.to_d.abs
    end

    # A bill takes money out of its account and a salary brings it in; a
    # recurring transfer does both, out of one account and into the other.
    # Both sides share the key, so a change applies to the whole transfer.
    def series_flows(series, date, amount, key, name: series.display_name)
      outflow = series.amount.to_d.positive? || series.destination_account_id.present?
      # A charge on a card is paid from the main account in the end.
      source_account = card_ids.include?(series.account_id) ? main_account : accounts_by_id[series.account_id]
      list = []

      if series.account_id.nil? || source_account
        list << Flow.new(date: date, account: source_account, amount: outflow ? amount : -amount, name: name, source: :recurring, key: key)
      end

      if (destination = accounts_by_id[series.destination_account_id])
        list << Flow.new(date: date, account: destination, amount: -amount, name: name, source: :recurring, key: key)
      end

      list
    end

    # ---- 2. One-off movements typed by the user ----

    def planned_flows
      family.forecast_items.where(account_id: account_ids, date: window).map do |item|
        Flow.new(date: item.date, account: accounts_by_id[item.account_id], amount: item.signed_amount, name: item.name,
                 source: :planned, record: item)
      end
    end

    # ---- 3. Everyday variable spending ----

    # One line a month per account, on the month's last day, for the months
    # whose last day is in the window. This month's line is what is left of
    # the estimate after what has already been spent.
    # One line a month, in the main account, with the variable spending of
    # all the accounts and cards together. Fulas Bank: an account left out of
    # the totals ("none" in Editar tabla) is left out here too: a pass-through
    # account, like the one where the payslip deductions come in and go out,
    # has spending whose income is not counted, which would inflate the line.
    def variable_flows
      return [] unless include_variable && main_account

      estimate = Forecast::VariableEstimate.new(family, accounts: counted_accounts + card_accounts, today: today)

      months.filter_map do |month|
        date = month.end_of_month
        next unless window.cover?(date)

        amount = estimate.combined_monthly(month)
        amount -= estimate.combined_spent(month) if month == today.beginning_of_month
        next unless amount.positive?

        Flow.new(date: date, account: main_account, amount: amount.round(2), name: variable_name(month),
                 source: :variable, key: ForecastAdjustment.variable_key(main_account, month))
      end
    end

    def card_ids
      @card_ids ||= card_accounts.map(&:id)
    end

    def months
      list = []
      month = today.beginning_of_month

      while month <= through
        list << month
        month = month.next_month
      end

      list
    end

    def variable_name(month)
      I18n.t("forecasts.variable_line", month: I18n.l(month, format: "%B %Y"))
    end

    # ---- 4. The debt plan ----

    def debt_plan_flows
      return [] unless debt_plan

      account = accounts_by_id[debt_plan.account_id] || main_account
      return [] unless account

      payments = debt_plan.payments.map do |date, loan, amount|
        [ date, I18n.t("forecasts.debt_plan_line", loan: loan), amount ]
      end
      contributions = debt_plan.contributions.map do |date, names, amount|
        [ date, I18n.t("forecasts.debt_plan_extra_line", name: names), amount ]
      end

      (payments + contributions).filter_map do |date, name, amount|
        next unless window.cover?(date)

        Flow.new(date: date, account: account, amount: amount, name: name, source: :debt_plan)
      end
    end

    # ---- 5. Credit card statements and instalments ----

    def card_flows
      card_accounts.flat_map do |card|
        cycle = CreditCard::Cycle.new(card, today: today)
        next [] unless cycle.configured?

        account = accounts_by_id[card.credit_card.payment_account_id] || main_account
        next [] unless account

        statement_flows(card, cycle, account) + financing_flows(card, cycle, account)
      end
    end

    # The purchases already made: the open statement and the last one while
    # it has not been charged. Later purchases are in "Gastos varios".
    def statement_flows(card, cycle, account)
      month = cycle.statement_month_for(today)
      cycle.statements_between(month.prev_month, month).filter_map do |statement|
        next unless window.cover?(statement.charged_on) && statement.amount.positive?

        Flow.new(date: statement.charged_on, account: account, amount: statement.amount.round(2), source: :card, card: card,
                 name: I18n.t("forecasts.card_statement_line", card: card.name, month: I18n.l(statement.closes_on, format: "%B %Y")))
      end
    end

    def financing_flows(card, cycle, account)
      card.card_financings.flat_map do |financing|
        financing.charges(cycle).filter_map do |charge|
          next unless window.cover?(charge.date)

          name = if charge.kind == :fee
            I18n.t("forecasts.card_fee_line", name: financing.name)
          else
            I18n.t("forecasts.card_installment_line", name: financing.name, number: charge.number, count: financing.installments_count)
          end
          Flow.new(date: charge.date, account: account, amount: charge.amount.round(2), name: name, source: :card, card: card)
        end
      end
    end

    # ---- 6. Insurance instalments ----

    def insurance_flows
      family.insurances.active.where(payment_frequency: Insurance::CUSTOM_FREQUENCY).includes(:insurance_payments).flat_map do |insurance|
        account = insurance_account(insurance)
        next [] unless account

        # An instalment already paid (charged early) is not expected again.
        paid = insurance.insurance_payments.select(&:paid?).map(&:due_on)

        charges = insurance.installment_charges_between((today - OVERDUE_LOOKBACK)..[ through, insurance.last_charge_day ].compact.min)
        charges.reject { |date, *| paid.include?(date) }.filter_map do |date, amount, number, count|
          on = expected_date(date, insurance.payment_account_id || account.id)
          next unless on

          name = I18n.t("forecasts.insurance_line", name: insurance.name, number: number, count: count)
          Flow.new(date: on, account: account, amount: to_account_currency(amount, account), source: :insurance,
                   key: ForecastAdjustment.insurance_key(insurance, date), name: overdue_name(name, date, on))
        end
      end
    end

    # Fulas Bank: a policy paid every month, quarter, half year or year (see
    # Insurance#periodic_charges_between), unless a recurring movement of
    # about the same amount already pays it.
    def policy_flows
      family.insurances.active.where.not(payment_frequency: Insurance::CUSTOM_FREQUENCY).where.not(premium: nil).flat_map do |insurance|
        account = insurance_account(insurance)
        next [] if account.nil? || paid_by_recurring?(insurance.premium.to_d)

        insurance.periodic_charges_between(window).map do |date, amount|
          Flow.new(date: date, account: account, amount: to_account_currency(amount, account), source: :insurance,
                   key: ForecastAdjustment.insurance_key(insurance, date), name: insurance.name)
        end
      end
    end

    # ---- 7. Loans ----

    # Fulas Bank: each loan's instalment, every month on its payment day, in
    # the main account, until the loan is paid off. Not when the debt plan
    # feeds the forecast (it has its own payments), nor when a recurring
    # movement already pays it.
    def loan_flows
      return [] if debt_plan || main_account.nil?

      family.accounts.visible.where(accountable_type: "Loan").includes(:accountable).flat_map do |loan_account|
        loan = loan_account.accountable
        payment = loan.monthly_payment&.amount || loan.payment_amount
        next [] if payment.blank? || !payment.to_d.positive? || loan.finished?(as_of: today)
        next [] if paid_by_recurring?(payment.to_d, destination: loan_account)

        loan_payment_days(loan).map do |date|
          Flow.new(date: date, account: main_account, amount: to_account_currency(Money.new(payment, loan_account.currency), main_account),
                   source: :loan, key: ForecastAdjustment.loan_key(loan_account, date),
                   name: I18n.t("forecasts.loan_line", name: loan_account.name))
        end
      end
    end

    # The loan's payment days in the window: its day of the month (or its
    # start's), up to its last instalment when the term is known.
    def loan_payment_days(loan)
      day = loan.payment_day || loan.start_date&.day || 1
      remaining = loan.remaining_months(as_of: today)
      last = remaining ? today.advance(months: remaining) : through

      months.filter_map do |month|
        date = month.change(day: [ day, month.end_of_month.day ].min)
        date if window.cover?(date) && date <= last
      end
    end

    # A recurring movement in force that already pays this: towards the
    # loan's account, or of about the same amount.
    def paid_by_recurring?(amount, destination: nil)
      recurring_in_force.any? do |series|
        (destination && series.destination_account_id == destination.id) ||
          (series.amount.to_d.abs - amount).abs <= amount * SAME_AMOUNT_TOLERANCE
      end
    end

    def recurring_in_force
      @recurring_in_force ||= family.recurring_transactions.where(status: "active").to_a
    end

    # The account it is charged to, if the forecast shows it; a card's
    # charges are paid from the main account in the end, as is a policy with
    # no account set.
    def insurance_account(insurance)
      accounts_by_id[insurance.payment_account_id] || main_account
    end

    def to_account_currency(money, account)
      return money.amount if money.currency.iso_code == account.currency

      money.exchange_to(account.currency).amount
    rescue Money::ConversionError
      money.amount
    end

    # ---- The user's changes to the lines above ----

    def adjustments
      @adjustments ||= ForecastAdjustment.where(family_id: family.id).index_by(&:key)
    end

    # Another date (still inside the window, or the line goes), amount (in
    # the same direction) or name, or left out.
    def adjusted(list)
      return list if adjustments.empty?

      list.filter_map do |flow|
        adjustment = adjustments[flow.key]
        next flow unless adjustment

        date = adjustment.date || flow.date
        next unless window.cover?(date)

        amount = flow.amount
        amount = flow.inflow? ? -adjustment.amount.to_d : adjustment.amount.to_d if adjustment.amount

        flow.with(date: date, amount: amount, name: adjustment.name.presence || flow.name,
                  skipped: adjustment.skipped, adjusted: true)
      end
    end
end
