# Fulas Bank: one change of a Scenario, from `starts_on` (and up to `ends_on`
# when it has one):
#
#   stop_recurring  a recurring movement stops (a subscription, a loan
#                   instalment paid as a recurring movement).
#   change_amount   a recurring movement costs, or brings in, `amount` each
#                   time (a pay rise, a new premium).
#   cancel_loan     a loan is paid off that day: its instalments stop, and
#                   what is left to pay goes out of the account at once. That
#                   is what the schedule says is pending then (pending) or an
#                   amount typed in (manual).
#   add_movement    an income or expense, once or every month or year (a new
#                   car, a rent, a side income).
#   adjust_variable each month's "Gastos varios" goes up (spending) or down
#                   (inflow) by `amount`.
#
# See Scenario::Effect for how each one changes the forecast's lines.
class ScenarioChange < ApplicationRecord
  KINDS = %w[cancel_loan stop_recurring change_amount add_movement adjust_variable].freeze
  NATURES = %w[outflow inflow].freeze
  FREQUENCIES = %w[once monthly yearly].freeze
  PAYOFF_MODES = %w[pending manual].freeze

  belongs_to :scenario, inverse_of: :scenario_changes
  belongs_to :recurring_transaction, optional: true
  belongs_to :loan_account, class_name: "Account", optional: true
  belongs_to :account, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :nature, inclusion: { in: NATURES }
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :payoff_mode, inclusion: { in: PAYOFF_MODES }
  validates :starts_on, presence: true
  validates :recurring_transaction, presence: true, if: -> { kind.in?(%w[stop_recurring change_amount]) }
  validates :loan_account, presence: true, if: -> { kind == "cancel_loan" }
  validates :name, presence: true, if: -> { kind == "add_movement" }
  validates :amount, numericality: { greater_than: 0 }, if: :amount_required?
  validate :ends_after_start
  validate :records_belong_to_family

  def amount_required?
    kind.in?(%w[change_amount add_movement adjust_variable]) || (kind == "cancel_loan" && payoff_mode == "manual")
  end

  def inflow?
    nature == "inflow"
  end

  # The amount on the bank's side, as the forecast's lines: positive when
  # money goes out.
  def signed_amount
    inflow? ? -amount.to_d : amount.to_d
  end

  def covers?(date)
    date >= starts_on && (ends_on.nil? || date <= ends_on)
  end

  # What a loan cancelled on `starts_on` still owes: the schedule's balance
  # after the last instalment before that day, or the loan's balance today
  # when it has no schedule (or no instalment before that day).
  def pending_loan_balance
    loan = loan_account&.accountable
    return 0.to_d unless loan

    payment = loan.amortization_schedule&.payments&.select { |each| each.date < starts_on }&.last
    (payment&.ending_balance || loan_account.balance).to_d.abs
  end

  # What cancelling the loan costs: the pending balance, or the amount typed
  # in.
  def payoff_amount
    payoff_mode == "manual" ? amount.to_d : pending_loan_balance
  end

  private
    def ends_after_start
      return if ends_on.nil? || starts_on.nil? || ends_on >= starts_on

      errors.add(:ends_on, :before_start)
    end

    def records_belong_to_family
      family = scenario&.family
      return unless family

      errors.add(:recurring_transaction, :invalid) if recurring_transaction && recurring_transaction.family_id != family.id
      errors.add(:loan_account, :invalid) if loan_account && (loan_account.family_id != family.id || loan_account.accountable_type != "Loan")
      errors.add(:account, :invalid) if account && account.family_id != family.id
    end
end
