# Fulas Bank: how a scenario's changes read on its page.
module ForecastScenariosHelper
  def scenario_money(amount, currency = Current.family.currency, precision: 2)
    format_money(Money.new(amount, currency), precision: precision)
  end

  def scenario_change_title(change)
    case change.kind
    when "cancel_loan"
      t("forecast_scenarios.changes.cancel_loan", name: change.loan_account&.name)
    when "stop_recurring"
      t("forecast_scenarios.changes.stop_recurring", name: change.recurring_transaction&.display_name)
    when "change_amount"
      t("forecast_scenarios.changes.change_amount", name: change.recurring_transaction&.display_name, amount: scenario_money(change.amount))
    when "add_movement"
      t("forecast_scenarios.changes.add_movement.#{change.nature}.#{change.frequency}", name: change.name, amount: scenario_money(change.amount))
    when "adjust_variable"
      t("forecast_scenarios.changes.adjust_variable.#{change.nature}", amount: scenario_money(change.amount))
    end
  end

  def scenario_change_detail(change)
    parts = []
    parts << (change.ends_on ? t("forecast_scenarios.changes.between", from: l(change.starts_on, format: "%-d/%m/%Y"), to: l(change.ends_on, format: "%-d/%m/%Y")) :
                               t("forecast_scenarios.changes.from", date: l(change.starts_on, format: "%-d/%m/%Y")))
    if change.kind == "cancel_loan"
      key = change.payoff_mode == "manual" ? "payoff_manual" : "payoff_pending"
      parts << t("forecast_scenarios.changes.#{key}", amount: scenario_money(change.payoff_amount, change.loan_account&.currency || Current.family.currency))
    end
    parts << t("forecast_scenarios.changes.account", name: change.account.name) if change.account
    parts.join(" · ")
  end

  # Positive in green, negative in red, for the differences.
  def scenario_difference_class(amount)
    return "text-secondary" if amount.zero?

    amount.positive? ? "text-success" : "text-destructive"
  end

  def scenario_signed_money(amount, precision: 0)
    text = scenario_money(amount, precision: precision)
    amount.positive? ? "+#{text}" : text
  end
end
