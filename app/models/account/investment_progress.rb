# Fulas Bank: what an investment account had put in, and what it had gained,
# on each day of its chart. Hovering over a day shows, as BBVA does for its
# savings policies:
#   - what the investment was worth that day ("Tenía invertidos");
#   - what it had gained so far ("Llevaba ganados"): worth minus put in;
#   - the money put in up to that day ("Llevaba aportados").
#
# "Put in" is the same as on the Inversiones page and in the yearly return
# (InvestmentsOverview::AnnualReturn#contribution_flows): the money that went
# into the account minus the money taken out (or, for an account recorded
# purchase by purchase, its buys minus its sales), plus what the account was
# already worth on its first day. Adding those up day by day gives what had
# been put in by each date.
#
# An account holding funds by participaciones (InvestmentFund) is left out:
# only today's "Total aportado" of its funds is known, not its history.
class Account::InvestmentProgress
  ACCOUNT_TYPES = InvestmentsOverview::ACCOUNT_TYPES

  attr_reader :account

  def initialize(account)
    @account = account
  end

  # Whether there is anything to show: an investment account with money put in.
  def applies?
    ACCOUNT_TYPES.include?(account.accountable_type) &&
      !account.family.investment_funds.where(account_id: account.id).exists? &&
      flows.any?
  end

  # @return [Money] the money put in up to and including `date`
  def contributed_on(date)
    index = dates.bsearch_index { |each| each > date } || dates.size
    Money.new(index.zero? ? 0 : running_totals[index - 1], account.currency)
  end

  # Adds each day's figures to a series of the account's value (the chart's
  # "balance" view) and returns it.
  def annotate(series)
    return series unless applies?

    series.values.each { |value| value.details = details_for(value) }
    series
  end

  private
    def details_for(value)
      contributed = contributed_on(value.date)
      gain = value.value - contributed

      [
        { key: "value", label: I18n.t("UI.account.chart.investment.value"), value: value.value },
        { key: "gain", label: I18n.t("UI.account.chart.investment.gain"), value: gain, percent_formatted: percent(gain, contributed) },
        { key: "contributed", label: I18n.t("UI.account.chart.investment.contributed"), value: contributed }
      ]
    end

    def percent(gain, contributed)
      return unless contributed.amount.positive?

      ActiveSupport::NumberHelper.number_to_percentage(gain.amount / contributed.amount * 100, precision: 2, locale: I18n.locale)
    end

    # [[date, amount]] by date, money put in negative (the investor's side).
    def flows
      @flows ||= InvestmentsOverview::AnnualReturn.new([ account ], currency: account.currency)
                                                  .contribution_flows(account)
                                                  .sort_by(&:first)
    end

    def dates
      @dates ||= flows.map(&:first)
    end

    # Money put in up to each flow, positive.
    def running_totals
      @running_totals ||= flows.each_with_object([]) do |(_, amount), totals|
        totals << (totals.last || 0) - amount
      end
    end
end
