class Vehicle < ApplicationRecord
  include Accountable

  # Miles only where they are the road unit; elsewhere (e.g. DEFAULT_COUNTRY=ES)
  # new vehicles start in kilometres.
  MILE_COUNTRIES = %w[US GB LR MM].freeze
  FUEL_TYPES = %w[gasoline diesel hybrid electric lpg].freeze

  attribute :mileage_unit, :string, default: -> {
    country = RegionalDefaults.country
    country.present? && MILE_COUNTRIES.exclude?(country) ? "km" : "mi"
  }

  has_many :logs, class_name: "Vehicle::Log", dependent: :destroy
  has_many :maintenance_items, class_name: "Vehicle::MaintenanceItem", dependent: :destroy

  validates :fuel_type, inclusion: { in: FUEL_TYPES }, allow_blank: true
  validate :purchase_price_not_negative

  normalizes :license_plate, with: ->(value) { value.strip.upcase.presence }

  def logbook(as_of: Date.current)
    Vehicle::Logbook.new(self, as_of: as_of)
  end

  # Litres for combustion engines, kWh for electric ones.
  def energy_unit
    fuel_type == "electric" ? "kWh" : "L"
  end

  # Keeps the recorded mileage in step with the highest odometer reading in
  # the logbook, so the overview never shows an older figure than the last
  # refuel or service.
  def advance_mileage_to!(odometer)
    return if odometer.blank?
    return if mileage_value.present? && mileage_value >= odometer

    update_column(:mileage_value, odometer)
  end

  def mileage
    Measurement.new(mileage_value, mileage_unit) if mileage_value.present?
  end

  # What the car cost: the price typed in its details or, failing that, the
  # first value the account was given.
  def purchase_price
    return Money.new(self[:purchase_price], account.currency) if self[:purchase_price].present?

    first_valuation_amount
  end

  def purchase_price_recorded?
    self[:purchase_price].present?
  end

  # Value lost since the purchase (negative if it is worth more now).
  def depreciation
    purchase_price - account.balance_money
  end

  class << self
    def color
      "#F23E94"
    end

    def icon
      "car-front"
    end

    def classification
      "asset"
    end
  end

  private
    # Checked on the stored number: `purchase_price` itself answers a Money.
    def purchase_price_not_negative
      return if self[:purchase_price].nil? || self[:purchase_price] >= 0

      errors.add(:purchase_price, :greater_than_or_equal_to, count: 0)
    end

    def first_valuation_amount
      account.entries.valuations.order(:date).first&.amount_money || account.balance_money
    end
end
