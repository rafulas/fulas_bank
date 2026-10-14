module DebtPlansHelper
  # The total owed month by month, for the chart: today, then after each
  # month's payments.
  def debt_plan_series(schedule, currency, today: Date.current)
    values = [ { date: today, value: Money.new(schedule.total_balance, currency) } ] +
             schedule.months.map { |month| { date: month.date, value: Money.new(month.total_balance, currency) } }
    values << { date: today + 1, value: values.first[:value] } if values.size < 2

    Series.from_raw_values(values, interval: "1 month")
  end

  def debt_plan_strategy_options
    DebtPlan::Schedule::STRATEGIES.map { |strategy| [ t("debt_plans.strategies.#{strategy}.name"), strategy ] }
  end

  # The recurring movement chosen for a loan, or the one that already pays
  # into it.
  def debt_plan_selected_series(plan, account, recurring_transactions)
    plan.setting(account, :recurring_transaction_id).presence ||
      recurring_transactions.find { |series| series.destination_account_id == account.id }&.id
  end

  def debt_plan_money(amount, currency, precision: 2)
    format_money(Money.new(amount, currency), precision: precision)
  end
end
