# One line in a vehicle's logbook: a refuel, a workshop service or another
# running cost (insurance, road tax, tolls...).
#
# A log can be linked to the bank transaction that paid for it (`entry`), so
# the money is recorded once, by the bank import, and the logbook adds what the
# bank does not know: odometer, litres, the service done. The link, and the
# suggestions the app makes on its own, live in BankChargeLinkable.
class Vehicle::Log < ApplicationRecord
  include Monetizable, BankChargeLinkable

  KINDS = %w[fuel service expense].freeze
  CATEGORIES = %w[insurance road_tax inspection parking toll washing fine accessories other].freeze

  monetize :amount, :unit_price

  # Scanned invoices and receipts: same formats and limits as a transaction's.
  MAX_ATTACHMENTS = Transaction::MAX_ATTACHMENTS_PER_TRANSACTION
  MAX_ATTACHMENT_SIZE = Transaction::MAX_ATTACHMENT_SIZE
  ATTACHMENT_TYPES = Transaction::ALLOWED_CONTENT_TYPES

  has_many_attached :attachments

  belongs_to :vehicle
  belongs_to :maintenance_item, class_name: "Vehicle::MaintenanceItem", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :date, :currency, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { greater_than: 0 }, allow_nil: true
  validates :unit_price, numericality: { greater_than: 0 }, allow_nil: true
  validates :odometer, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :category, inclusion: { in: CATEGORIES }, if: :expense?
  validate :maintenance_item_belongs_to_vehicle
  validate :attachments_are_acceptable, if: -> { attachments.attached? }

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

  def asset_account
    vehicle&.account
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

    def advance_vehicle_mileage
      vehicle.advance_mileage_to!(odometer)
    end

    def maintenance_item_belongs_to_vehicle
      return if maintenance_item.blank? || maintenance_item.vehicle_id == vehicle_id

      errors.add(:maintenance_item, :invalid)
    end

    def attachments_are_acceptable
      errors.add(:attachments, :too_many, max: MAX_ATTACHMENTS) if attachments.size > MAX_ATTACHMENTS

      attachments.each do |attachment|
        if attachment.byte_size > MAX_ATTACHMENT_SIZE
          errors.add(:attachments, :too_large, filename: attachment.filename.to_s, max_mb: MAX_ATTACHMENT_SIZE / 1.megabyte)
        elsif ATTACHMENT_TYPES.exclude?(attachment.content_type)
          errors.add(:attachments, :invalid_format, filename: attachment.filename.to_s)
        end
      end
    end
end
