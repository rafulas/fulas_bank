# Fulas Bank: the «Informe» of the Resumen, a snapshot of where things stand
# built to be read on screen and pasted into a spreadsheet. For the accounts
# the user picks:
#   - summary: cash, investments, other assets, debt and net worth today,
#     with the period's income, spending and savings rate;
#   - balances: each account today and a month ago;
#   - net_worth: assets, debt and net worth at the end of each of the last
#     twelve months;
#   - loans: what is still owed, the instalment and when each loan ends (and
#     the debt plan's debt-free date);
#   - investments: value, what was put in and the gain of each account;
#   - stock_plans: the years of each share plan (see StockPlan);
#   - cash_flow: the period's spending by main category against what is
#     normal (see Category::SpendingVsNormal);
#   - forecast: the expected total at the end of each of the next twelve
#     months and the lowest point (see Forecast);
#   - fixed: this month's recurring payments by group (see MonthPlan).
#
# Each section is a Block: a header row and data rows, which is what the
# page's tables show and what «Copiar para Sheets» copies (see #to_tsv).
# Amounts are in the family's currency.
class StatusReport
  SECTIONS = %w[summary balances net_worth loans investments stock_plans cash_flow forecast fixed].freeze
  PERIODS = %w[last_month current_month last_90_days current_year].freeze
  HISTORY_MONTHS = 12
  FORECAST_MONTHS = 12

  LIQUID_TYPES = %w[Depository CreditCard].freeze
  INVESTMENT_TYPES = %w[Investment Crypto].freeze

  # A table: `headers`, `rows` of cells (String, Date, Numeric or nil) and
  # how each column reads on screen (`formats`: :text, :date, :month,
  # :money, :percent or :number).
  Block = Data.define(:headers, :rows, :formats) do
    def to_tsv(header: true)
      StatusReport::Tsv.dump(header ? [ headers, *rows ] : rows)
    end

    def empty?
      rows.empty?
    end
  end

  Totals = Data.define(:liquidity, :investments, :other_assets, :debt, :net_worth)

  attr_reader :family, :user, :accounts, :sections, :period_key, :today

  # `accounts`: the accounts to cover, already limited to what `user` sees.
  def initialize(family, user:, accounts:, sections: SECTIONS, period_key: "last_month", today: Date.current)
    @family = family
    @user = user
    @accounts = accounts.to_a
    @sections = SECTIONS & Array(sections)
    @period_key = PERIODS.include?(period_key) ? period_key : "last_month"
    @today = today
  end

  def currency
    family.currency
  end

  def show?(section)
    sections.include?(section)
  end

  def period
    @period ||= case period_key
    when "current_month" then Period.current_month_for(family)
    when "last_month" then Period.last_month_for(family)
    else Period.from_key(period_key)
    end
  end

  # ---- summary ----

  def totals
    @totals ||= totals_from(accounts.to_h { |account| [ account.id, to_family_currency(account.balance, account.currency) ] })
  end

  def totals_a_month_ago
    @totals_a_month_ago ||= totals_from(balances_on([ today.prev_month ])[today.prev_month])
  end

  def summary
    Block.new(
      headers: header_names(:date, :liquidity, :investments, :other_assets, :debt, :net_worth, :income, :spending, :savings_rate),
      formats: %i[date money money money money money money money percent],
      rows: [ [ today, totals.liquidity, totals.investments, totals.other_assets, totals.debt, totals.net_worth,
                analysis.income.amount, analysis.spent.amount, analysis.savings_rate ] ]
    )
  end

  # ---- balances ----

  def balances
    month_ago = balances_on([ today.prev_month ])[today.prev_month]
    Block.new(
      headers: header_names(:account, :type, :balance, :month_ago, :change),
      formats: %i[text text money money money],
      rows: accounts.map do |account|
        now = signed(account, to_family_currency(account.balance, account.currency))
        before = signed(account, month_ago[account.id] || 0)
        [ account.name, account.accountable.singular_display_name, now, before, now - before ]
      end
    )
  end

  # ---- net worth ----

  def net_worth
    @net_worth ||= begin
      dates = history_dates
      known = balances_on(dates - [ today ])
      rows = dates.map do |date|
        values = date == today ? accounts.to_h { |account| [ account.id, to_family_currency(account.balance, account.currency) ] } : known[date]
        totals = totals_from(values)
        cards = debt_owed_as_cash(values)
        [ date, totals.liquidity + totals.investments + totals.other_assets + cards, totals.debt + cards, totals.net_worth ]
      end
      Block.new(headers: header_names(:date, :assets, :debt, :net_worth), rows: rows, formats: %i[date money money money])
    end
  end

  def net_worth_series
    Series.from_raw_values(net_worth.rows.map { |date, _, _, value| { date: date, value: Money.new(value, currency) } }, interval: "1 month")
  end

  # ---- loans ----

  def loan_rows
    @loan_rows ||= LoansOverview.new(family, user: user, today: today).rows.select { |row| account_ids.include?(row.account.id) }
  end

  def loans
    Block.new(
      headers: header_names(:loan, :pending, :payment, :ends_on),
      formats: %i[text money money month],
      rows: loan_rows.map do |row|
        [ row.account.name, to_family_currency(row.pending.amount, row.pending.currency),
          row.monthly_payment && to_family_currency(row.monthly_payment.amount, row.monthly_payment.currency), row.payoff_date ]
      end
    )
  end

  # The debt plan's debt-free date, when there is a plan.
  def debt_free_on
    family.debt_plan&.schedule(user, today: today)&.payoff_date
  rescue StandardError
    nil
  end

  # ---- investments ----

  def investment_rows
    @investment_rows ||= InvestmentsOverview.new(family, user: user).rows.select { |row| account_ids.include?(row.account.id) }
  end

  def investments
    Block.new(
      headers: header_names(:account, :value, :contributed, :gain, :return),
      formats: %i[text money money money percent],
      rows: investment_rows.map do |row|
        value = to_family_currency(row.value.amount, row.value.currency)
        contributed = row.contributed && to_family_currency(row.contributed.amount, row.contributed.currency)
        [ row.account.name, value, contributed, contributed && value - contributed, row.return_ratio && (row.return_ratio * 100).round(1) ]
      end
    )
  end

  # ---- share plans ----

  def stock_plans
    plans = family.stock_plans.includes(:grants, :security).where(investment_account_id: account_ids).alphabetically
    Block.new(
      headers: header_names(:plan, :delivered_on, :shares, :shares_source, :sell_on, :value),
      formats: %i[text date number text date money],
      rows: plans.flat_map do |plan|
        plan.grants.map do |grant|
          value = grant.value(today: today)
          [ plan.name, grant.granted_on, grant.total_shares(today: today),
            (I18n.t("status_reports.shares_sources.#{grant.shares_source(today: today)}") if grant.shares_source(today: today)),
            grant.sell_on, value && to_family_currency(value, plan.currency) ]
        end
      end
    )
  end

  # ---- income and spending ----

  def analysis
    @analysis ||= Category::Analysis.new(family, period: period, account_ids: account_ids, today: today)
  end

  def spending_vs_normal
    @spending_vs_normal ||= Category::SpendingVsNormal.new(family, account_ids: account_ids, month: analysis.end_date, today: today)
  end

  def cash_flow
    normal = spending_vs_normal.rows.index_by(&:id)
    single_month = period.start_date.beginning_of_month == period.end_date.beginning_of_month
    Block.new(
      headers: header_names(:category, :spent, *(single_month ? %i[normal vs_normal] : [])),
      formats: [ :text, :money, *(single_month ? %i[money percent] : []) ],
      rows: analysis.spending_slices.map do |slice|
        row = [ slice.name, slice.amount ]
        if single_month
          usual = normal[slice.id]&.normal
          row += [ usual, usual&.positive? ? ((slice.amount - usual) / usual * 100).round(1) : nil ]
        end
        row
      end
    )
  end

  # ---- forecast ----

  def forecast_accounts
    accounts.select { |account| Forecast::ACCOUNT_TYPES.include?(account.accountable_type) }
  end

  def forecast_cards
    accounts.select { |account| Forecast::CARD_TYPES.include?(account.accountable_type) }
  end

  def forecast_month_ends
    (1..FORECAST_MONTHS).map { |offset| (today >> offset).end_of_month.clamp(today, today >> FORECAST_MONTHS) }.uniq
  end

  def cushion
    user.preferences&.dig(Forecast::CUSHION_PREFERENCE).presence&.to_d
  end

  # `forecast`: built by the controller the way the Forecast page builds it.
  def forecast_block(forecast)
    Block.new(
      headers: header_names(:date, :expected_total, :cushion),
      formats: %i[date money money],
      rows: forecast_month_ends.map { |date| [ date, forecast.total_on(date).amount, cushion ] }
    )
  end

  # ---- fixed payments ----

  def fixed
    plan = MonthPlan.new(family, user: user, month: today, today: today)
    Block.new(
      headers: header_names(:group, :monthly),
      formats: %i[text money],
      rows: plan.groups.reject { |group| group.key == "income" }.map do |group|
        [ I18n.t("month_plans.show.groups.#{group.key}"), group.payments.reject(&:income?).sum(&:amount) ]
      end
    )
  end

  private
    def account_ids
      @account_ids ||= accounts.map(&:id)
    end

    def header_names(*keys)
      keys.map { |key| I18n.t("status_reports.headers.#{key}") }
    end

    # The last day of each of the last HISTORY_MONTHS months, and today.
    def history_dates
      ((HISTORY_MONTHS - 1).downto(1).map { |offset| (today << offset).end_of_month } + [ today ]).uniq
    end

    # { date => { account_id => balance in the family's currency } } from
    # the stored daily balances (an account without one that day counts 0).
    def balances_on(dates)
      found = Balance.where(account_id: account_ids, date: dates).pluck(:account_id, :date, :balance, :currency)
      dates.index_with { {} }.tap do |result|
        found.each { |id, date, balance, from| result[date][id] = to_family_currency(balance, from) }
      end
    end

    def totals_from(values)
      by_type = Hash.new(BigDecimal(0))
      net = BigDecimal(0)
      accounts.each do |account|
        balance = values[account.id] || 0
        net += signed(account, balance)
        bucket = if LIQUID_TYPES.include?(account.accountable_type) then :liquidity
        elsif INVESTMENT_TYPES.include?(account.accountable_type) then :investments
        elsif account.liability? then :debt
        else :other_assets
        end
        by_type[bucket] += bucket == :debt ? balance.to_d : signed(account, balance)
      end
      Totals.new(liquidity: by_type[:liquidity], investments: by_type[:investments], other_assets: by_type[:other_assets],
                 debt: by_type[:debt], net_worth: net)
    end

    # What the cards owe: they count in cash (negative there), so the net
    # worth table moves it to the debt column and keeps only what is owned
    # as assets.
    def debt_owed_as_cash(values)
      accounts.select { |account| account.liability? && LIQUID_TYPES.include?(account.accountable_type) }
              .sum { |account| (values[account.id] || 0).to_d }
    end

    # What an account adds to net worth: a liability's balance is what is owed.
    def signed(account, balance)
      account.liability? ? -balance.to_d : balance.to_d
    end

    def to_family_currency(amount, from)
      amount = amount.respond_to?(:amount) ? amount.amount : amount
      from = from.respond_to?(:iso_code) ? from.iso_code : from.to_s
      return amount.to_d if from.blank? || from == currency.to_s

      Money.new(amount, from).exchange_to(currency).amount
    rescue Money::ConversionError
      amount.to_d
    end
end
