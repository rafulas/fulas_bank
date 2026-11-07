# Fulas Bank: Vencimientos y garantías. A dated thing to renew or keep an
# eye on — the car's ITV, a warranty, the DNI, a tax, the boiler check-up —
# with a reminder some days before. One that repeats (the ITV every year or
# two, the DNI every ten) moves to its next date when marked done; one that
# does not is kept as done.
#
# Insurance renewals are not copied here: Deadline::Upcoming lists them
# next to these, from the policies themselves.
class Deadline < ApplicationRecord
  include Monetizable

  KINDS = %w[itv warranty document tax maintenance other].freeze
  REMIND_DAYS = [ 7, 15, 30, 60, 90 ].freeze
  REPEAT_MONTHS = [ 6, 12, 24, 48, 60, 120 ].freeze
  ICONS = {
    "itv" => "car", "warranty" => "badge-check", "document" => "id-card",
    "tax" => "landmark", "maintenance" => "wrench", "other" => "calendar-clock"
  }.freeze

  belongs_to :family
  belongs_to :account, optional: true

  monetize :amount

  validates :name, :due_on, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :remind_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 365 }
  validates :repeat_months, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 240 }, allow_nil: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :account_in_family

  before_validation :inherit_currency

  scope :pending, -> { where(completed_on: nil) }
  scope :completed, -> { where.not(completed_on: nil) }
  scope :chronological, -> { order(:due_on, :name) }

  def self.default_kind_for(account)
    account&.accountable_type == "Vehicle" ? "itv" : "other"
  end

  def icon
    ICONS.fetch(kind, ICONS["other"])
  end

  def completed?
    completed_on.present?
  end

  def repeats?
    repeat_months.present?
  end

  def days_left(today = Date.current)
    (due_on - today).to_i
  end

  def overdue?(today = Date.current)
    !completed? && due_on < today
  end

  # Within its reminder window (or past its date) and not done.
  def due_soon?(today = Date.current)
    !completed? && due_on <= today + remind_days.days
  end

  # Done: a repeating one moves on to its next date after today, the rest
  # are kept as done.
  def complete!(today = Date.current)
    if repeats?
      next_due = due_on
      next_due = next_due.advance(months: repeat_months) while next_due <= today
      update!(due_on: next_due, completed_on: nil)
    else
      update!(completed_on: today)
    end
  end

  def reopen!
    update!(completed_on: nil)
  end

  private
    def inherit_currency
      self.currency ||= account&.currency || family&.currency
    end

    def account_in_family
      errors.add(:account, :invalid) if account && account.family_id != family_id
    end
end
