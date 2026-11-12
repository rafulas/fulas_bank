# Fulas Bank: the "Inversiones" screen, a first version. Every investment and
# crypto account the user can see, with its value today, what has been put
# into it, the gain and the return; the main positions of the accounts that
# have them; and the totals.
#
# "Put into it" is the net of the money movements of the account (transfers
# in minus transfers out). Buying and selling inside the account does not
# count. An account without brokerage cash (shares bought and sold straight
# from the bank) uses what the shares it still holds cost, by FIFO: its
# gain is the one of what it holds today, and what its sales gained, which
# left the account, is shown apart (Row#realized). An account with no money movements but with positions (shares
# recorded purchase by purchase) uses what those positions cost instead;
# with neither, there is nothing to compare against and no gain is shown.
# An account holding funds by participaciones (InvestmentFund) uses the
# "Total aportado" typed for its funds, as the funds table does.
class InvestmentsOverview
  ACCOUNT_TYPES = %w[Investment Crypto].freeze
  TOP_HOLDINGS = 5

  Row = Data.define(:account, :value, :contributed, :realized) do
    def gain
      contributed && value - contributed
    end

    # Fulas Bank: the gain of what is held plus what the sales gained.
    def total_gain
      gain && realized && gain + realized
    end

    def return_ratio
      return nil unless contributed&.amount&.positive?

      (gain.amount / contributed.amount).to_f
    end

    def holdings
      account.current_holdings.includes(:security).first(InvestmentsOverview::TOP_HOLDINGS)
    end
  end

  attr_reader :family, :user

  def initialize(family, user:)
    @family = family
    @user = user
  end

  def currency
    family.currency
  end

  def rows
    @rows ||= accounts.map do |account|
      net_in = funds_cost(account) ||
        (account.brokerage_cash? ? (contributions[account.id] || holdings_cost(account)) : realized_gains.open_cost(account))
      sold = realized_gains.realized_for(account) unless account.brokerage_cash?
      Row.new(
        account: account,
        value: Money.new(account.balance.to_d, account.currency),
        contributed: (Money.new(net_in, account.currency) if net_in),
        realized: (Money.new(sold, account.currency) if sold)
      )
    end.sort_by { |row| -row.value.amount }
  end

  def total_value
    sum(rows.map(&:value))
  end

  # Only the accounts that have contributions, so the gain compares like
  # with like.
  def total_contributed
    sum(rows.filter_map(&:contributed))
  end

  def total_gain
    with_contributions = rows.select(&:contributed)
    sum(with_contributions.map(&:value)) - total_contributed
  end

  # Fulas Bank: what every sale ever gained, by FIFO, in the accounts whose
  # sales left them (see Row#realized). nil when none sold.
  def total_realized
    with_sales = rows.filter_map(&:realized)
    sum(with_sales) if with_sales.any?
  end

  # Fulas Bank: the gain of what is held today plus what the sales gained.
  def total_gain_with_sales
    total_realized && total_gain + total_realized
  end

  # Fulas Bank: the accounts the gain leaves out, having no contributions
  # to compare with (a pension plan or a savings policy with no movements).
  def rows_without_contributions
    rows.reject(&:contributed)
  end

  def total_return_ratio
    return nil unless total_contributed.amount.positive?

    (total_gain.amount / total_contributed.amount).to_f
  end

  # Fulas Bank: the yearly return taking into account when each euro went in
  # (see InvestmentsOverview::AnnualReturn), for every account and in total.
  def annual_return
    @annual_return ||= InvestmentsOverview::AnnualReturn.new(accounts, currency: currency)
  end

  # Fulas Bank: the buys and sales whose bank movement the app proposed
  # (TradeLinker) and the user has not confirmed yet, newest first.
  def suggested_trades
    @suggested_trades ||= Trade.joins(:entry)
                               .where(entries: { account_id: accounts.map(&:id) }, bank_entry_suggested: true)
                               .includes(entry: :account, bank_entry: :account)
                               .order("entries.date DESC")
                               .to_a
  end

  # The funds held by participaciones in these accounts (InvestmentFund).
  def funds
    @funds ||= family.investment_funds.where(account_id: accounts.select { |account| account.accountable_type == "Investment" }.map(&:id))
                     .includes(:account).alphabetically.to_a
  end

  def any_stale_fund?
    funds.any?(&:stale?)
  end

  # [ [label, value], ... ] by kind of account (fund, pension plan...), biggest first.
  def by_kind
    rows.group_by { |row| row.account.short_subtype_label.presence || row.account.accountable_type }
        .map { |label, list| [ label, sum(list.map(&:value)) ] }
        .sort_by { |_, money| -money.amount }
  end

  private
    def accounts
      @accounts ||= family.accounts.accessible_by(user).visible.where(accountable_type: ACCOUNT_TYPES).alphabetically.to_a
    end

    # { account_id => money put in (positive) } from the accounts' money
    # movements; accounts without any are left out.
    def contributions
      @contributions ||= family.entries
                               .where(account_id: accounts.map(&:id), entryable_type: "Transaction", excluded: false)
                               .excluding_split_parents
                               .group(:account_id)
                               .sum(:amount)
                               .transform_values { |amount| -amount.to_d }
    end

    # Fulas Bank: buys and sales, worked out lot by lot (FIFO), for what the
    # shares still held cost and what the sales gained.
    def realized_gains
      @realized_gains ||= InvestmentsOverview::RealizedGains.new(family, user: user)
    end

    # Fulas Bank: what was put into the account's funds (their "Total
    # aportado"), so the header agrees with the funds table. nil when the
    # account holds no funds or a fund has no cost typed in.
    def funds_cost(account)
      list = funds.select { |fund| fund.account_id == account.id }
      return if list.empty? || list.any? { |fund| fund.cost.nil? }

      list.sum { |fund| fund.cost.to_d }
    end

    # What the current positions cost, for an account recorded only with
    # purchases (no money moved in): nil unless every position's cost is known.
    def holdings_cost(account)
      holdings = account.current_holdings.to_a
      return if holdings.empty?

      costs = holdings.map { |holding| (cost = holding.avg_cost) && holding.qty.to_d * cost.amount }
      costs.sum if costs.none?(&:nil?)
    end

    def sum(amounts)
      Money.new(amounts.sum { |money| to_family_currency(money) }, currency)
    end

    def to_family_currency(money)
      return money.amount if money.currency.iso_code == currency

      money.exchange_to(currency).amount
    rescue Money::ConversionError
      money.amount
    end
end
