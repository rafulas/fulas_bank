module ForecastsHelper
  SOURCE_TONES = { recurring: :info, planned: :violet, variable: :amber, debt_plan: :fuchsia, card: :indigo, insurance: :green, loan: :fuchsia }.freeze

  # An expected amount from the user's side: income with a plus sign, spending
  # with a minus sign.
  def forecast_signed_amount(amount, currency)
    money = Money.new(amount.to_d.abs, currency)
    amount.to_d.negative? ? "−#{format_money(money)}" : "+#{format_money(money)}"
  end

  # Fulas Bank: `open_months` nil shows every month line by line; a list
  # folds the months after the first year but those (see Forecast#table_rows).
  def forecast_table_rows(forecast, ledger_rows, open_months: nil)
    forecast.table_rows(ledger_rows, open_months: open_months)
  end

  # Fulas Bank: the table again with `month` opened or folded, scrolled to
  # it: in the page's frame (#ledger) or in the wide dialog (#table). The
  # period, account and other choices of the page go along.
  def forecast_month_toggle_path(month, open_months:, expanded:)
    months = open_months.include?(month) ? open_months - [ month ] : open_months + [ month ]
    params = request.query_parameters.slice("period", "until", "account_id", "variable")
                    .merge("open" => months.map { |each| each.strftime("%Y-%m") }, "focus" => month.strftime("%Y-%m"))
    expanded ? table_forecast_path(params) : ledger_forecast_path(params)
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
