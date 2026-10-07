# One line in a vehicle's logbook: a refuel, a workshop service or another
# running cost (insurance, road tax, tolls...).
#
# A log can be linked to the bank transaction that paid for it (`entry`), so
# the money is recorded once, by the bank import, and the logbook adds what the
# bank does not know: odometer, litres, the service done.
class Vehicle::Log < ApplicationRecord
  include Monetizable

  KINDS = %w[fuel service expense].freeze
  CATEGORIES = %w[insurance road_tax inspection parking toll washing fine accessories other].freeze

  # Bank charges up to this many days either side of the log's date are
  # offered as its payment, closest amount first.
  MATCH_WINDOW = 15.days
  MATCH_LIMIT = 15

  monetize :amount, :unit_price

  belongs_to :vehicle
  belongs_to :maintenance_item, class_name: "Vehicle::MaintenanceItem", optional: true
  belongs_to :entry, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :date, :currency, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { greater_than: 0 }, allow_nil: true
  validates :unit_price, numericality: { greater_than: 0 }, allow_nil: true
  validates :odometer, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :category, inclusion: { in: CATEGORIES }, if: :expense?
  validates :entry_id, uniqueness: true, allow_nil: true
  validate :maintenance_item_belongs_to_vehicle
  validate :entry_belongs_to_family

  before_validation :inherit_currency
  before_validation :take_amount_from_entry
  before_validation :complete_fuel_figures, if: :fuel?
  after_save :advance_vehicle_mileage

  scope :chronological, -> { order(:date, :odometer, :created_at) }
  scope :reverse_chronological, -> { order(date: :desc, odometer: :desc, created_at: :desc) }

  KINDS.each do |kind_name|
    define_method("#{kind_name}?") { kind == kind_name }
    scope kind_name.pluralize, -> { where(kind: kind_name) }
  end

  def family
    vehicle.account.family
  end

  # Outgoing bank transactions of the family around this log's date that are
  # not already linked to another log: closest amount first (when the log has
  # one), then closest date.
  def candidate_entries(scope: family.entries, limit: MATCH_LIMIT)
    return [] if date.blank?

    linked = Vehicle::Log.where.not(entry_id: nil).where.not(id: id).select(:entry_id)

    candidates = scope.where(entryable_type: "Transaction")
                      .where(date: (date - MATCH_WINDOW)..(date + MATCH_WINDOW))
                      .where("entries.amount > 0")
                      .where.not(id: linked)
                      .includes(:account)
                      .order(date: :desc)
                      .limit(200)
                      .to_a

    target = amount.to_d
    candidates.sort_by do |entry|
      amount_gap = target.positive? ? ((entry.amount - target).abs / target) : 0
      [ amount_gap, (entry.date - date).abs ]
    end.first(limit)
  end

  private
    def inherit_currency
      self.currency ||= vehicle&.account&.currency
    end

    # Fills whichever of litres, price per litre and total is missing from the
    # other two, as the refuel form only needs any two of them.
    def complete_fuel_figures
      if amount.to_d.zero? && quantity.present? && unit_price.present?
        self.amount = (quantity * unit_price).round(2)
      elsif quantity.blank? && unit_price.present? && amount.to_d.positive?
        self.quantity = (amount / unit_price).round(3)
      elsif unit_price.blank? && quantity.present? && amount.to_d.positive?
        self.unit_price = (amount / quantity).round(4)
      end
    end

    def take_amount_from_entry
      return if entry.blank? || amount.to_d.positive?

      self.amount = entry.amount.abs
    end

    def advance_vehicle_mileage
      vehicle.advance_mileage_to!(odometer)
    end

    def maintenance_item_belongs_to_vehicle
      return if maintenance_item.blank? || maintenance_item.vehicle_id == vehicle_id

      errors.add(:maintenance_item, :invalid)
    end

    def entry_belongs_to_family
      return if entry.blank? || vehicle.blank?
      return if entry.account.family_id == vehicle.account&.family_id

      errors.add(:entry, :invalid)
    end
end
