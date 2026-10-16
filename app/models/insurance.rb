# Fulas Bank: an insurance policy of the family (car, motorbike, home, life,
# health...). The Seguros page lists them all with what they cost a year and
# when they renew.
#
# A policy that covers an asset is tied to that asset's account: the car
# insurance to the car (a Vehicle account), the home insurance to the house
# (a Property account). The asset's page then shows its insurance.
class Insurance < ApplicationRecord
  include Monetizable

  KINDS = %w[car motorcycle home life health accident travel pet liability burial other].freeze

  # The kinds that insure an asset, and the type of account that asset is.
  # Any other kind may still be tied to a vehicle or a property, or to none.
  ASSET_TYPES = { "car" => "Vehicle", "motorcycle" => "Vehicle", "home" => "Property" }.freeze
  LINKABLE_TYPES = ASSET_TYPES.values.uniq.freeze

  # How many times a year the premium is paid.
  FREQUENCIES = { "annual" => 1, "semiannual" => 2, "quarterly" => 4, "monthly" => 12 }.freeze

  # A renewal this close is flagged, so there is time to compare prices.
  RENEWAL_NOTICE = 30.days

  ICONS = {
    "car" => "car", "motorcycle" => "bike", "home" => "home", "life" => "heart-handshake",
    "health" => "stethoscope", "accident" => "bandage", "travel" => "plane", "pet" => "paw-print",
    "liability" => "scale", "burial" => "flower", "other" => "shield"
  }.freeze

  # The policy itself, receipts, the green card: same formats and limits as
  # the files attached to a transaction.
  MAX_DOCUMENTS = Transaction::MAX_ATTACHMENTS_PER_TRANSACTION
  MAX_DOCUMENT_SIZE = Transaction::MAX_ATTACHMENT_SIZE
  DOCUMENT_TYPES = Transaction::ALLOWED_CONTENT_TYPES

  monetize :premium

  belongs_to :family
  belongs_to :account, optional: true
  has_many_attached :documents

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :payment_frequency, inclusion: { in: FREQUENCIES.keys }
  validates :premium, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :account_is_an_insurable_asset
  validate :documents_are_acceptable, if: -> { documents.attached? }

  before_validation :inherit_currency
  normalizes :name, :insurer, :policy_number, :coverage, :assistance_phone, with: ->(value) { value.strip.presence }

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :alphabetically, -> { order(:name) }

  # The kind a new policy for this asset most likely is.
  def self.kind_for(account)
    ASSET_TYPES.key(account&.accountable_type) || "other"
  end

  # Before saving, the currency is the asset's or the family's.
  def currency
    super || account&.currency || family&.currency
  end

  def icon
    ICONS.fetch(kind, "shield")
  end

  def payments_per_year
    FREQUENCIES.fetch(payment_frequency, 1)
  end

  # What the policy costs in a year, whatever the payment frequency.
  def annual_cost
    Money.new(premium.to_d * payments_per_year, currency) if premium
  end

  def monthly_cost
    Money.new(premium.to_d * payments_per_year / 12, currency) if premium
  end

  # Policies renew every year on the same day: the next renewal is the
  # renewal date typed in, moved forward by whole years until it is today
  # or later.
  def next_renewal(today = Date.current)
    return if renewal_date.nil?
    return renewal_date if renewal_date >= today

    date = renewal_date.advance(years: today.year - renewal_date.year)
    date < today ? date.advance(years: 1) : date
  end

  def days_to_renewal(today = Date.current)
    (next_renewal(today) - today).to_i if renewal_date
  end

  def renews_soon?(today = Date.current)
    active? && renewal_date.present? && next_renewal(today) <= today + RENEWAL_NOTICE
  end

  private
    def inherit_currency
      self[:currency] ||= currency
    end

    def account_is_an_insurable_asset
      return if account.nil?

      if account.family_id != family_id || LINKABLE_TYPES.exclude?(account.accountable_type)
        errors.add(:account, :invalid)
      elsif (expected = ASSET_TYPES[kind]) && account.accountable_type != expected
        errors.add(:account, :wrong_type, kind: I18n.t("insurances.kinds.#{kind}").downcase)
      end
    end

    def documents_are_acceptable
      errors.add(:documents, :too_many, max: MAX_DOCUMENTS) if documents.size > MAX_DOCUMENTS

      documents.each do |document|
        if document.byte_size > MAX_DOCUMENT_SIZE
          errors.add(:documents, :too_large, filename: document.filename.to_s, max_mb: MAX_DOCUMENT_SIZE / 1.megabyte)
        elsif DOCUMENT_TYPES.exclude?(document.content_type)
          errors.add(:documents, :invalid_format, filename: document.filename.to_s)
        end
      end
    end
end
