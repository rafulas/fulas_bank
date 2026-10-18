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

  # Fulas Bank: or paid in instalments the user sets, each with its day and
  # amount (see #installments). Some insurers split the yearly premium in
  # three payments 45 days apart, which no fixed frequency describes.
  CUSTOM_FREQUENCY = "custom".freeze
  PAYMENT_FREQUENCIES = (FREQUENCIES.keys + [ CUSTOM_FREQUENCY ]).freeze
  MAX_INSTALLMENTS = 24

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
  # Fulas Bank: where the instalments are charged (a current account or a
  # card); the Forecast expects them there, or in its main account.
  belongs_to :payment_account, class_name: "Account", optional: true
  has_many_attached :documents
  # Fulas Bank: how each instalment was paid (see InsurancePayment).
  has_many :insurance_payments, dependent: :delete_all

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :payment_frequency, inclusion: { in: PAYMENT_FREQUENCIES }
  validate :installments_are_valid, if: :custom_payments?
  validate :payment_account_is_the_familys
  validates :premium, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :account_is_an_insurable_asset
  validate :documents_are_acceptable, if: -> { documents.attached? }
  validate :ending_needs_a_renewal_date

  before_validation :inherit_currency
  before_validation :set_end_from_renewal
  normalizes :name, :insurer, :policy_number, :coverage, :assistance_phone, with: ->(value) { value.strip.presence }

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :alphabetically, -> { order(:name) }
  scope :ended, ->(today = Date.current) { active.where(ends_on: ..today) }

  # Fulas Bank: the policies that will not be renewed and whose day has come
  # are no longer in force (ExpireInsurancesJob, every day).
  def self.expire_ended!(today = Date.current)
    ended(today).update_all(active: false, updated_at: Time.current)
  end

  # Fulas Bank: "No se renovará" in the form. Unticked, the policy ends at
  # its next renewal (`ends_on`); ticked again, it renews as usual.
  def renews
    ends_on.nil?
  end
  alias_method :renews?, :renews

  def renews=(value)
    @renews_requested = ActiveModel::Type::Boolean.new.cast(value)
  end

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
    return installments.size if custom_payments?

    FREQUENCIES.fetch(payment_frequency, 1)
  end

  def custom_payments?
    payment_frequency == CUSTOM_FREQUENCY
  end

  # The instalments of a policy paid in custom instalments, soonest first:
  # [{ "date" => "2026-09-01", "amount" => "150.0" }, ...]. Rows of the form
  # left blank are dropped; amounts may be typed with a decimal comma.
  def installments=(rows)
    rows = rows.values if rows.respond_to?(:values) && !rows.is_a?(Array)
    list = Array(rows).filter_map do |row|
      row = row.to_h.stringify_keys
      date = row["date"].to_s.strip
      amount = row["amount"].to_s.strip.tr(",", ".")
      next if date.blank? && amount.blank?

      { "date" => date, "amount" => amount }
    end

    super(list.sort_by { |row| row["date"] })
  end

  # Each instalment as [Date, Money], soonest first; unreadable rows left out.
  def installment_schedule
    Array(installments).filter_map do |row|
      date = Date.iso8601(row["date"].to_s)
      amount = BigDecimal(row["amount"].to_s)
      [ date, Money.new(amount, currency) ]
    rescue ArgumentError, TypeError, Date::Error
      nil
    end
  end

  # What the policy costs in a year, whatever the payment frequency. Paid in
  # custom instalments, it is what they add up to.
  def annual_cost
    if custom_payments?
      schedule = installment_schedule
      return if schedule.empty?

      Money.new(schedule.sum { |_, amount| amount.amount }, currency)
    elsif premium
      Money.new(premium.to_d * payments_per_year, currency)
    end
  end

  def monthly_cost
    annual = annual_cost
    Money.new(annual.amount / 12, currency) if annual
  end

  # Every charge of the custom instalments between two days, for the
  # Forecast: each instalment on its day, and again a year later, and so on,
  # as the policy renews. Charges before the instalment's own first day do
  # not exist. Each is [date, Money, number, count], number counting from 1.
  def installment_charges_between(range)
    return [] unless custom_payments?

    schedule = installment_schedule
    schedule.each_with_index.flat_map do |(first_date, amount), index|
      years = [ range.first.year - first_date.year - 1, 0 ].max
      charges = []
      date = first_date.advance(years: years)

      while date <= [ range.last, last_charge_day ].compact.min
        charges << [ date, amount, index + 1, schedule.size ] if range.cover?(date)
        years += 1
        date = first_date.advance(years: years)
      end

      charges
    end
  end

  # One instalment on its day, with how it was paid (nil: not yet).
  Instalment = Data.define(:date, :amount, :number, :count, :payment) do
    def paid?
      payment&.paid? || false
    end

    def suggested?
      payment.present? && payment.suggested? && payment.entry_id.present?
    end

    # :paid, :suggested (a charge proposed by the app), :overdue (its day
    # passed a few days ago with no charge) or :upcoming.
    def status(today = Date.current)
      return :paid if paid?
      return :suggested if suggested?

      date < today - InsuranceLinker::MATCH_DAYS ? :overdue : :upcoming
    end
  end

  # Fulas Bank: the charges of a policy paid every month, quarter, half year
  # or year, as [Date, Money], in `range`: on its renewal day (or start day)
  # and every period from there, the premium each time, none from the day it
  # ends.
  def periodic_charges_between(range)
    anchor = renewal_date || start_date
    return [] if custom_payments? || anchor.nil? || premium.blank?

    step = 12 / payments_per_year
    last = [ range.last, last_charge_day ].compact.min
    periods = ((range.first.year * 12 + range.first.month) - (anchor.year * 12 + anchor.month)).fdiv(step).floor - 1

    charges = []
    loop do
      date = anchor.advance(months: periods * step)
      break if date > last

      charges << [ date, Money.new(premium, currency) ] if date >= range.first
      periods += 1
    end
    charges
  end

  # The last day a charge can fall on: the day before it ends, if it ends.
  def last_charge_day
    ends_on && ends_on - 1
  end

  # The instalments of the last year and the next one to come: what the
  # policy's page shows, to see which have been charged.
  def recent_instalments(today = Date.current)
    return [] unless custom_payments?

    past = installment_charges_between((today - 1.year + 1.day)..today)
    upcoming = installment_charges_between((today + 1)..(today + 1.year)).min_by(&:first)
    payments = insurance_payments.index_by(&:due_on)

    (past + [ upcoming ].compact).sort_by(&:first).map do |date, amount, number, count|
      Instalment.new(date: date, amount: amount, number: number, count: count, payment: payments[date])
    end
  end

  # Instalments whose day has passed with no charge for them.
  def overdue_instalments(today = Date.current)
    recent_instalments(today).select { |instalment| instalment.status(today) == :overdue }
  end

  # The bank charges that could have paid an instalment, for the user to
  # choose: outgoing, around its day, not paying another instalment, the
  # closest amount first.
  def payment_candidates(date, amount, limit: 3)
    InsuranceLinker.new(family).candidates(self, date, amount.amount, window: 15.days, tolerance: nil).first(limit)
  end

  # The next instalment to be charged, as [Date, Money], for a policy paid in
  # custom instalments. The instalments repeat every year on the same days,
  # as the policy renews, so a date already past counts again a year on.
  def next_installment(today = Date.current)
    return unless custom_payments?

    installment_schedule.map do |date, amount|
      upcoming = date
      upcoming = upcoming.advance(years: 1) while upcoming < today
      [ upcoming, amount ]
    end.min_by(&:first)
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

    def set_end_from_renewal
      return if @renews_requested.nil?

      self.ends_on = @renews_requested ? nil : (ends_on || next_renewal)
    end

    def ending_needs_a_renewal_date
      errors.add(:renewal_date, :needed_to_end) if @renews_requested == false && ends_on.nil?
    end

    def account_is_an_insurable_asset
      return if account.nil?

      if account.family_id != family_id || LINKABLE_TYPES.exclude?(account.accountable_type)
        errors.add(:account, :invalid)
      elsif (expected = ASSET_TYPES[kind]) && account.accountable_type != expected
        errors.add(:account, :wrong_type, kind: I18n.t("insurances.kinds.#{kind}").downcase)
      end
    end

    # A policy paid in custom instalments needs at least one, each with a day
    # and an amount that is not negative.
    def installments_are_valid
      rows = Array(installments)
      if rows.empty?
        errors.add(:installments, :blank)
      elsif rows.size > MAX_INSTALLMENTS
        errors.add(:installments, :too_many, max: MAX_INSTALLMENTS)
      elsif installment_schedule.size != rows.size || installment_schedule.any? { |_, amount| amount.amount.negative? }
        errors.add(:installments, :invalid)
      end
    end

    def payment_account_is_the_familys
      return if payment_account.nil?
      return if payment_account.family_id == family_id && %w[Depository CreditCard].include?(payment_account.accountable_type)

      errors.add(:payment_account, :invalid)
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
