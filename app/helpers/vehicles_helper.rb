module VehiclesHelper
  def vehicle_fuel_type_options
    Vehicle::FUEL_TYPES.map { |type| [ t("vehicles.fuel_types.#{type}"), type ] }
  end

  def vehicle_log_category_options
    Vehicle::Log::CATEGORIES.map { |category| [ t("vehicles.logs.categories.#{category}"), category ] }
  end

  def vehicle_log_title(log)
    case log.kind
    when "fuel" then t("vehicles.logs.kinds.fuel")
    when "service" then log.maintenance_item&.name || log.notes.to_s.lines.first&.strip.presence || t("vehicles.logs.kinds.service")
    else t("vehicles.logs.categories.#{log.category}", default: t("vehicles.logs.kinds.expense"))
    end
  end

  def vehicle_log_icon(log)
    { "fuel" => "fuel", "service" => "wrench", "expense" => "receipt" }.fetch(log.kind, "car-front")
  end

  # The bank charges a log can be linked to, labelled so the user can tell
  # them apart: date, description, amount and account. The charge already
  # linked stays in the list even when it no longer looks like a match.
  def vehicle_log_entry_options(log)
    entries = log.candidate_entries(scope: Current.accessible_entries)
    entries = [ log.entry, *entries.reject { |entry| entry.id == log.entry_id } ] if log.entry.present?

    entries.map do |entry|
      label = [
        format_date(entry.date),
        entry.name,
        format_money(entry.amount_money),
        entry.account.name
      ].join(" · ")

      [ label, entry.id ]
    end
  end

  # The usual workshop jobs the vehicle does not track yet, offered as
  # one-click starting points.
  def vehicle_missing_presets(vehicle)
    tracked = vehicle.maintenance_items.map { |item| item.name.to_s.downcase.strip }

    Vehicle::MaintenanceItem::PRESETS.reject do |preset|
      tracked.include?(t("vehicles.maintenance_items.presets.#{preset[:key]}").downcase)
    end
  end

  def vehicle_distance(value, vehicle)
    return if value.nil?

    "#{number_with_delimiter(value.round)} #{vehicle.mileage_unit}"
  end

  def vehicle_consumption(value, vehicle)
    return if value.nil?

    t("vehicles.logbook.consumption_value", value: number_with_precision(value, precision: 1), unit: vehicle.energy_unit, distance: vehicle.mileage_unit)
  end

  # What the consumption chart draws and shows on hover, already formatted in
  # the user's locale so the script only places it.
  def vehicle_consumption_chart_data(logbook, vehicle)
    {
      points: logbook.consumption_series.map do |point|
        {
          date: point.date.iso8601,
          date_label: format_date(point.date),
          value: point.per_100.to_f,
          value_label: vehicle_consumption(point.per_100, vehicle),
          distance_label: vehicle_distance(point.distance, vehicle),
          quantity_label: "#{number_with_precision(point.quantity, precision: 2)} #{vehicle.energy_unit}",
          odometer_label: vehicle_distance(point.odometer, vehicle)
        }
      end,
      average: logbook.average_consumption&.to_f,
      average_label: vehicle_consumption(logbook.average_consumption, vehicle)
    }
  end

  def maintenance_status_pill(status)
    tone = { overdue: :error, soon: :warning, ok: :success, unknown: :neutral }.fetch(status.state)

    render DS::Pill.new(label: t("vehicles.maintenance_items.states.#{status.state}"), tone: tone, marker: false)
  end

  def maintenance_status_detail(status, vehicle)
    parts = []

    if status.km_left
      parts << if status.km_left.negative?
        t("vehicles.maintenance_items.status.km_over", distance: vehicle_distance(-status.km_left, vehicle))
      else
        t("vehicles.maintenance_items.status.km_left", distance: vehicle_distance(status.km_left, vehicle))
      end
    end

    if status.due_on
      key = status.overdue? && status.due_on < Date.current ? "was_due" : "due_by"
      parts << t("vehicles.maintenance_items.status.#{key}", date: format_date(status.due_on))
    end

    parts.presence&.join(" · ") || t("vehicles.maintenance_items.status.not_recorded")
  end
end
