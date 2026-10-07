# Figures derived from a vehicle's logbook: odometer, real fuel consumption,
# cost per kilometre, this year's running costs and workshop due dates.
#
# Consumption is measured between full tanks: the fuel put in after one full
# tank, up to and including the next one, is what was burnt over that
# distance. Partial refuels in between are added to the next full tank.
class Vehicle::Logbook
  ConsumptionPoint = Data.define(:date, :odometer, :per_100)

  attr_reader :vehicle, :as_of

  def initialize(vehicle, as_of: Date.current)
    @vehicle = vehicle
    @as_of = as_of
  end

  def logs
    @logs ||= vehicle.logs.includes(:maintenance_item, entry: :account).chronological.to_a
  end

  def empty?
    logs.empty? && vehicle.maintenance_items.empty?
  end

  def currency
    vehicle.account.currency
  end

  def odometer
    [ vehicle.mileage_value, *logs.filter_map(&:odometer) ].compact.max
  end

  def consumption_series
    @consumption_series ||= measured_segments.map { |segment| segment[:point] }
  end

  # Average over every measured stretch, weighted by distance.
  def average_consumption
    segments = measured_segments
    distance = segments.sum { |segment| segment[:distance] }
    return if distance.zero?

    (segments.sum { |segment| segment[:quantity] } / distance * 100).round(2)
  end

  def total_spent
    Money.new(logs.sum { |log| log.amount.to_d }, currency)
  end

  # Everything spent divided by the distance the logbook covers, from the
  # first odometer reading to the latest.
  def cost_per_km
    readings = logs.filter_map(&:odometer)
    return if readings.size < 2

    distance = readings.max - readings.min
    return if distance <= 0

    Money.new(logs.sum { |log| log.amount.to_d } / distance, currency)
  end

  # This calendar year's spending, by kind of log.
  def year_totals(year: as_of.year)
    totals = Vehicle::Log::KINDS.index_with { 0.to_d }
    logs.each { |log| totals[log.kind] += log.amount.to_d if log.date.year == year }
    totals.transform_values { |value| Money.new(value, currency) }
  end

  def year_total(year: as_of.year)
    Money.new(year_totals(year: year).values.sum(&:amount), currency)
  end

  def last_refuel
    logs.select(&:fuel?).max_by { |log| [ log.date, log.odometer.to_i ] }
  end

  def recent(limit = 5)
    logs.reverse.first(limit)
  end

  def maintenance_statuses
    @maintenance_statuses ||= vehicle.maintenance_items.alphabetically.map do |item|
      [ item, item.status(odometer: odometer, as_of: as_of) ]
    end
  end

  def maintenance_alerts
    maintenance_statuses.select { |_item, status| status.overdue? || status.soon? }
  end

  private
    def measured_segments
      @measured_segments ||= begin
        refuels = logs.select { |log| log.fuel? && log.odometer.present? && log.quantity.present? }
                      .sort_by { |log| [ log.odometer, log.date ] }

        segments = []
        last_full = nil
        pending = 0.to_d

        refuels.each do |refuel|
          pending += refuel.quantity if last_full
          next unless refuel.full_tank?

          if last_full
            distance = refuel.odometer - last_full.odometer
            if distance.positive? && pending.positive?
              segments << {
                distance: distance,
                quantity: pending,
                point: ConsumptionPoint.new(date: refuel.date, odometer: refuel.odometer, per_100: (pending / distance * 100).round(2))
              }
            end
          end

          last_full = refuel
          pending = 0.to_d
        end

        segments
      end
    end
end
