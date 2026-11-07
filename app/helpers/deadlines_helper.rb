module DeadlinesHelper
  # "Hoy", "Mañana", "En 12 días", "Venció hace 3 días".
  def deadline_days_label(days)
    if days.zero?
      t("deadlines.days.today")
    elsif days.negative?
      t("deadlines.days.overdue", count: days.abs)
    else
      t("deadlines.days.left", count: days)
    end
  end
end
