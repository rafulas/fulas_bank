# A recurring workshop job for one vehicle (oil change, tyres, ITV...) with
# how often it is due, by distance, by time or both. Services recorded in the
# logbook against the item move its "last done" point forward.
class Vehicle::MaintenanceItem < ApplicationRecord
  # Common jobs offered when adding an item, with typical intervals.
  PRESETS = [
    { key: "oil_change", interval_km: 15_000, interval_months: 12, match: /aceite|\boil\b/i },
    { key: "air_filter", interval_km: 30_000, interval_months: 24, match: /filtro\s+(de\s+)?aire|air filter/i },
    { key: "cabin_filter", interval_km: 15_000, interval_months: 12, match: /polen|habit[aá]culo|cabin/i },
    { key: "tyres", interval_km: 40_000, interval_months: nil, match: /neum[aá]tic|ruedas|tyre|tire/i },
    { key: "brake_pads", interval_km: 30_000, interval_months: nil, match: /pastilla|brake pad/i },
    { key: "timing_belt", interval_km: 120_000, interval_months: 60, match: /distribuci[oó]n|timing belt/i },
    { key: "inspection", interval_km: nil, interval_months: 24, match: /\bitv\b/i, category: "inspection" }
  ].freeze

  # An item counts as "due soon" within this share of its distance interval
  # (never less than SOON_MIN_KM) or within SOON_DAYS of its date.
  SOON_SHARE = 0.1
  SOON_MIN_KM = 1_000
  SOON_DAYS = 30

  Status = Data.define(:state, :km_left, :due_on, :progress) do
    def overdue? = state == :overdue
    def soon? = state == :soon
    def ok? = state == :ok
    def unknown? = state == :unknown
  end

  belongs_to :vehicle
  has_many :logs, class_name: "Vehicle::Log", dependent: :nullify

  validates :name, presence: true
  validates :interval_km, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :interval_months, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :last_done_odometer, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :has_an_interval

  scope :alphabetically, -> { order(:name) }

  # The latest of the manually entered "last done" point and the services
  # recorded in the logbook.
  def last_done
    service = logs.services.reverse_chronological.first
    manual = [ last_done_on, last_done_odometer ]

    return manual if service.nil?
    return [ service.date, service.odometer || last_done_odometer ] if last_done_on.nil? || service.date >= last_done_on

    manual
  end

  def status(odometer:, as_of: Date.current)
    done_on, done_km = last_done

    km_left = (done_km + interval_km - odometer if interval_km.present? && done_km.present? && odometer.present?)
    due_on = (done_on + interval_months.months if interval_months.present? && done_on.present?)

    return Status.new(state: :unknown, km_left: nil, due_on: nil, progress: 0) if km_left.nil? && due_on.nil?

    progress = [
      (1 - km_left.to_f / interval_km if km_left),
      ((as_of - done_on).to_f / (due_on - done_on) if due_on)
    ].compact.max.clamp(0, 1)

    state = if (km_left && km_left.negative?) || (due_on && due_on < as_of)
      :overdue
    elsif (km_left && km_left < [ SOON_MIN_KM, interval_km * SOON_SHARE ].max) || (due_on && due_on < as_of + SOON_DAYS.days)
      :soon
    else
      :ok
    end

    Status.new(state: state, km_left: km_left, due_on: due_on, progress: progress)
  end

  private
    def has_an_interval
      return if interval_km.present? || interval_months.present?

      errors.add(:base, :interval_required)
    end
end
