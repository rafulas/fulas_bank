# Fulas Bank: applies a Scenario's changes to the lines of a Forecast
# (Forecast::Flow), in order:
#
#   stop_recurring  the series' lines from the change's first day (up to its
#                   last, when it has one) go.
#   change_amount   those lines keep their day and direction, with the new
#                   amount.
#   cancel_loan     the loan's instalments go from that day: its own lines
#                   (Préstamos), the debt plan's payments for it and the
#                   recurring movements paying it. The payoff goes out of
#                   the account that day, as one line.
#   add_movement    one line, or one a month or a year, until the end date
#                   or the forecast's.
#   adjust_variable each month's "Gastos varios" line goes up or down (never
#                   below zero).
#
# A line left out by the user (skipped) is changed like the others: it still
# does not count.
class Scenario::Effect
  attr_reader :scenario, :forecast

  def initialize(scenario, forecast)
    @scenario = scenario
    @forecast = forecast
  end

  def apply(flows)
    scenario.scenario_changes.reduce(flows) { |list, change| apply_change(list, change) }
  end

  private
    def apply_change(list, change)
      case change.kind
      when "stop_recurring" then stop_recurring(list, change)
      when "change_amount" then change_amount(list, change)
      when "cancel_loan" then cancel_loan(list, change)
      when "add_movement" then list + added_flows(change)
      when "adjust_variable" then adjust_variable(list, change)
      else list
      end
    end

    def stop_recurring(list, change)
      list.reject { |flow| series_line?(flow, change.recurring_transaction_id) && change.covers?(flow.date) }
    end

    def change_amount(list, change)
      list.map do |flow|
        next flow unless series_line?(flow, change.recurring_transaction_id) && change.covers?(flow.date)

        flow.with(amount: flow.inflow? ? -change.amount.to_d : change.amount.to_d)
      end
    end

    def cancel_loan(list, change)
      loan_account = change.loan_account
      paying = forecast.recurring_paying(loan_account).map(&:id)

      kept = list.reject do |flow|
        next false unless flow.date >= change.starts_on

        loan_line = flow.source.in?([ :loan, :debt_plan ]) && flow.origin.to_s == loan_account.id.to_s
        loan_line || (flow.source == :recurring && paying.include?(flow.origin))
      end

      amount = change.payoff_amount
      return kept unless amount.positive? && forecast.window.cover?(change.starts_on)

      account = target_account(change)
      kept + [ Forecast::Flow.new(date: change.starts_on, account: account, amount: in_currency(amount, loan_account.currency, account),
                                  name: I18n.t("scenarios.lines.cancel_loan", name: loan_account.name), source: :scenario) ]
    end

    def added_flows(change)
      account = target_account(change)
      last = [ change.ends_on, forecast.through ].compact.min

      dates_for(change, last).filter_map do |date|
        next unless forecast.window.cover?(date)

        Forecast::Flow.new(date: date, account: account, amount: in_currency(change.signed_amount, change.scenario.family.currency, account),
                           name: change.name, source: :scenario)
      end
    end

    def dates_for(change, last)
      return [ change.starts_on ] if change.frequency == "once"

      step = change.frequency == "yearly" ? 12 : 1
      dates = []
      number = 0
      while (date = change.starts_on.advance(months: step * number)) <= last
        dates << date
        number += 1
      end
      dates
    end

    def adjust_variable(list, change)
      list.map do |flow|
        next flow unless flow.source == :variable && change.covers?(flow.date)

        flow.with(amount: [ flow.amount + change.signed_amount, 0.to_d ].max)
      end
    end

    def series_line?(flow, series_id)
      flow.source == :recurring && flow.origin.present? && flow.origin == series_id
    end

    # The account chosen, if the forecast shows it; the main account
    # otherwise.
    def target_account(change)
      forecast.accounts.find { |account| account.id == change.account_id } || forecast.main_account
    end

    def in_currency(amount, currency, account)
      return amount.to_d if account.nil? || currency == account.currency

      Money.new(amount, currency).exchange_to(account.currency).amount
    rescue Money::ConversionError
      amount.to_d
    end
end
