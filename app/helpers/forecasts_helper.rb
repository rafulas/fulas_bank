module ForecastsHelper
  SOURCE_TONES = { recurring: :info, planned: :violet, variable: :amber, debt_plan: :fuchsia, card: :indigo, insurance: :green }.freeze

  # An expected amount from the user's side: income with a plus sign, spending
  # with a minus sign.
  def forecast_signed_amount(amount, currency)
    money = Money.new(amount.to_d.abs, currency)
    amount.to_d.negative? ? "−#{format_money(money)}" : "+#{format_money(money)}"
  end

  def forecast_table_rows(forecast, ledger_rows)
    forecast.table_rows(ledger_rows)
  end

  def forecast_source_tone(source)
    SOURCE_TONES.fetch(source.to_sym, :neutral)
  end

  # Where a line of the table is edited: a one-off movement in its own form,
  # any other line as a change to what the app works out (its key, plus its
  # current values for the form to show).
  def forecast_line_edit_path(flow)
    return edit_forecast_item_path(flow.record) if flow.record
    return debt_plan_path if flow.source == :debt_plan
    # A card's statement or instalment changes on the card itself.
    return account_path(flow.card, tab: "card_statement") if flow.source == :card && flow.card

    edit_forecast_adjustment_path(key: flow.key, date: flow.date.iso8601, amount: flow.amount.abs.to_s, name: flow.name)
  end
end
