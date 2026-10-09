require "csv"

# Brings a vehicle's history over from the RoadTrip app, whose export is one
# CSV file split into sections: a title line ("COMBUSTIBLE", "MANTENIMIENTO",
# "Vehículo"...), a header line, the rows and a blank line. Fields are
# separated by semicolons and decimals use a comma ("52,1423").
#
# - Refuels become fuel logs (km, litres, price, total, full tank or not).
# - Maintenance records become workshop services, or running costs when
#   RoadTrip filed them as expenses (road tax, insurance...).
# - The licence plate in the vehicle's notes fills in an empty plate.
#
# Columns are read by position: RoadTrip keeps the same order whatever the
# language of the export, while the titles are translated.
#
# Two safeguards, because the history is years long and typed by hand:
# - An odometer reading that cannot be right (lower than the previous one or
#   thousands of km beyond it, like a digit typed twice) is left out of that
#   log and listed, so it does not wreck the consumption or the mileage.
# - Logs the vehicle already has (same kind, date and amount) are skipped, so
#   importing the same file twice, or after typing in the latest refuels by
#   hand, does not duplicate anything.
class Vehicle::RoadtripImport
  class InvalidFile < StandardError; end

  SIGNATURE = "ROAD TRIP CSV".freeze
  SECTIONS = {
    "COMBUSTIBLE" => :fuel, "FUEL" => :fuel,
    "MANTENIMIENTO" => :maintenance, "MAINTENANCE" => :maintenance,
    "VEHÍCULO" => :vehicle, "VEHICULO" => :vehicle, "VEHICLE" => :vehicle
  }.freeze

  # Column positions in each section.
  FUEL = { odometer: 0, date: 2, quantity: 3, unit_price: 5, amount: 6, partial: 7, notes: 9, location: 11 }.freeze
  MAINTENANCE = { description: 0, date: 1, odometer: 2, amount: 3, notes: 4, location: 5, type: 6 }.freeze
  VEHICLE = { notes: 3 }.freeze

  # RoadTrip's own record types that are workshop jobs.
  SERVICE_TYPES = %w[servicio service].freeze
  # Records filed as an expense that are still workshop jobs.
  WORKSHOP_WORDS = /neum[aá]tic|rueda|revisi[oó]n|aceite|pastilla|freno|bater[ií]a|filtro|tyre|tire|oil|brake/i

  # Running costs that stay running costs even when RoadTrip filed them as a
  # service (the ITV, for instance).
  FIXED_COSTS = %w[road_tax insurance inspection parking toll fine].freeze

  # Running-cost category by words in the description, first match wins
  # ("ITVM", a common typo for the IVTM road tax, must not read as the ITV).
  CATEGORY_WORDS = [
    [ "road_tax", /ivtm|itvm|impuesto|circulaci[oó]n|road tax/i ],
    [ "insurance", /seguro|p[oó]liza|insurance/i ],
    [ "inspection", /\bitv\b|inspecci[oó]n|inspection/i ],
    [ "parking", /parking|aparcamiento|estacionamiento/i ],
    [ "toll", /peaje|autopista|toll/i ],
    [ "washing", /lavado|lavadero|wash/i ],
    [ "fine", /multa|sanci[oó]n|fine/i ],
    [ "accessories", /accesorio|accessor/i ]
  ].freeze

  # A jump of more than this many km between two refuels is a typo, never a
  # real trip without refuelling (or ten times the usual distance, for a car
  # with an unusually large tank).
  MAX_JUMP_KM = 5_000
  MAX_JUMP_FACTOR = 10

  # A reading that was left out of its log. `reason` is :lower or :jump.
  Issue = Data.define(:date, :odometer, :reason)
  Summary = Data.define(:counts, :duplicates, :first_date, :last_date, :issues, :license_plate)

  attr_reader :vehicle

  def initialize(vehicle, content)
    @vehicle = vehicle
    @content = content.to_s
  end

  def logs
    parse
    @logs
  end

  def issues
    parse
    @issues
  end

  def license_plate
    parse
    @license_plate
  end

  # Logs in the file that the vehicle does not have yet.
  def new_logs
    @new_logs ||= begin
      seen = existing_keys
      logs.select { |attrs| seen.add?(key_for(attrs)) }
    end
  end

  def summary
    dates = logs.map { |attrs| attrs[:date] }

    Summary.new(
      counts: Vehicle::Log::KINDS.index_with { |kind| new_logs.count { |attrs| attrs[:kind] == kind } },
      duplicates: logs.size - new_logs.size,
      first_date: dates.min,
      last_date: dates.max,
      issues: issues,
      license_plate: (license_plate if vehicle.license_plate.blank?)
    )
  end

  # Creates the new logs and fills in the plate, all or nothing. Returns how
  # many logs were created.
  def import!
    Vehicle::Log.transaction do
      new_logs.each { |attrs| vehicle.logs.create!(attrs) }
      vehicle.update!(license_plate: license_plate) if vehicle.license_plate.blank? && license_plate.present?
    end

    new_logs.size
  end

  private
    def parse
      return if @parsed

      @logs = []
      @issues = []
      @license_plate = nil

      sections = read_sections
      raise InvalidFile, "no refuels or maintenance found" if sections[:fuel].blank? && sections[:maintenance].blank?

      fuel = Array(sections[:fuel]).filter_map { |row| fuel_log(row) }.sort_by { |attrs| attrs[:date] }
      highest = check_odometers(fuel)
      maintenance = Array(sections[:maintenance]).filter_map { |row| maintenance_log(row, highest) }

      @logs = (fuel + maintenance).sort_by { |attrs| [ attrs[:date], attrs[:odometer].to_i ] }
      @license_plate = plate_from(Array(sections[:vehicle]).first)
      @parsed = true
    end

    # { fuel: [rows], maintenance: [rows], vehicle: [rows] }, header lines
    # dropped.
    def read_sections
      rows = CSV.parse(text, col_sep: ";", liberal_parsing: true)
      raise InvalidFile, "not a RoadTrip export" unless rows.first&.first.to_s.strip.upcase.start_with?(SIGNATURE)

      sections = Hash.new { |hash, key| hash[key] = [] }
      current = nil
      expect_header = false

      rows.drop(1).each do |row|
        cells = row.map { |cell| cell.to_s.strip }

        if cells.all?(&:blank?)
          current = nil
        elsif cells.size == 1 && (section = SECTIONS[cells.first.upcase])
          current = section
          expect_header = true
        elsif expect_header
          expect_header = false
        elsif current
          sections[current] << cells
        end
      end

      sections
    rescue CSV::MalformedCSVError
      raise InvalidFile, "unreadable CSV"
    end

    # Exports are UTF-8, sometimes with a byte-order mark; older ones may be
    # Windows-1252.
    def text
      utf8 = @content.dup.force_encoding(Encoding::UTF_8)
      utf8 = @content.dup.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8) unless utf8.valid_encoding?
      utf8.delete_prefix("﻿")
    end

    def fuel_log(row)
      date = date_from(row[FUEL[:date]])
      amount = decimal(row[FUEL[:amount]])
      quantity = decimal(row[FUEL[:quantity]])
      return if date.nil? || (amount.nil? && quantity.nil?)

      {
        kind: "fuel",
        date: date,
        odometer: integer(row[FUEL[:odometer]]),
        quantity: (quantity if quantity&.positive?),
        unit_price: decimal(row[FUEL[:unit_price]]).then { |price| price if price&.positive? },
        amount: amount || BigDecimal("0"),
        full_tank: row[FUEL[:partial]].blank?,
        notes: [ row[FUEL[:notes]], row[FUEL[:location]] ].compact_blank.join("\n").presence
      }
    end

    def maintenance_log(row, highest_odometer)
      date = date_from(row[MAINTENANCE[:date]])
      description = row[MAINTENANCE[:description]].to_s.strip
      return if date.nil? || description.blank?

      odometer = integer(row[MAINTENANCE[:odometer]])
      if odometer && highest_odometer && odometer > highest_odometer
        @issues << Issue.new(date: date, odometer: odometer, reason: :jump)
        odometer = nil
      end

      notes = [ description, row[MAINTENANCE[:notes]], row[MAINTENANCE[:location]] ].compact_blank.join("\n")
      type = row[MAINTENANCE[:type]].to_s.strip.downcase
      category = category_for(description)
      service = !FIXED_COSTS.include?(category) && (SERVICE_TYPES.include?(type) || description.match?(WORKSHOP_WORDS))

      {
        kind: service ? "service" : "expense",
        category: (category unless service),
        date: date,
        odometer: odometer,
        amount: decimal(row[MAINTENANCE[:amount]]) || BigDecimal("0"),
        notes: notes
      }
    end

    # Drops readings that break the sequence of refuels (in date order) and
    # returns the highest believable reading, the ceiling for the workshop
    # records.
    def check_odometers(fuel)
      readings = fuel.filter_map { |attrs| attrs[:odometer] }
      gaps = readings.each_cons(2).map { |a, b| b - a }.select(&:positive?).sort
      usual = gaps.empty? ? 0 : gaps[gaps.size / 2]
      limit = [ MAX_JUMP_KM, usual * MAX_JUMP_FACTOR ].max

      previous = nil
      fuel.each do |attrs|
        odometer = attrs[:odometer]
        next if odometer.nil?

        reason = if previous && odometer < previous then :lower
        elsif previous && odometer - previous > limit then :jump
        end

        if reason
          @issues << Issue.new(date: attrs[:date], odometer: odometer, reason: reason)
          attrs[:odometer] = nil
        else
          previous = odometer
        end
      end

      previous && previous + limit
    end

    def category_for(description)
      CATEGORY_WORDS.find { |_category, words| description.match?(words) }&.first || "other"
    end

    def plate_from(row)
      notes = row&.dig(VEHICLE[:notes]).to_s
      notes[/(?:placa|matr[ií]cula|plate)\s*:\s*([A-Z0-9][A-Z0-9 -]{2,11})\s*$/i, 1]&.strip&.upcase
    end

    def existing_keys
      Set.new(vehicle.logs.map { |log| key_for(log) })
    end

    def key_for(record)
      record = record.symbolize_keys if record.is_a?(Hash)
      value = ->(name) { record.is_a?(Hash) ? record[name] : record.public_send(name) }

      [ value.(:kind), value.(:date), value.(:amount).to_d.round(2) ]
    end

    def date_from(value)
      match = value.to_s.match(/\A\s*(\d{4})-(\d{1,2})-(\d{1,2})/)
      Date.new(match[1].to_i, match[2].to_i, match[3].to_i) if match
    rescue Date::Error
      nil
    end

    def decimal(value)
      cleaned = value.to_s.strip.delete(" ").tr(",", ".")
      BigDecimal(cleaned) if cleaned.match?(/\A-?\d+(\.\d+)?\z/)
    end

    def integer(value)
      decimal(value)&.to_i
    end
end
