module MonthPlansHelper
  # Under each recurring payment, like Bilance: its date when paid, "Hoy",
  # "Vencido: 8 de octubre" when its date passed unpaid, or
  # "Previsto: 21 de octubre".
  def month_plan_payment_date(payment)
    date = l(payment.date, format: t("month_plans.show.long_date"))

    case payment.state
    when :paid then date
    when :today then t("month_plans.show.today")
    when :overdue then t("month_plans.show.overdue_on", date: date)
    else t("month_plans.show.expected_on", date: date)
    end
  end
end
