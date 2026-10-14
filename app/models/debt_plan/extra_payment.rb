# Fulas Bank: a one-off contribution to the debt plan, such as part of the
# bonus each March. With `repeats_until` it is repeated every year, in the
# same month, up to that date.
class DebtPlan::ExtraPayment < ApplicationRecord
  self.table_name = "debt_plan_extra_payments"

  MAX_REPEATS = 50

  belongs_to :debt_plan

  validates :date, :amount, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validate :repeats_after_date

  def dates
    return [ date ] if repeats_until.blank?

    (0...MAX_REPEATS).map { |years| date >> (12 * years) }.take_while { |each_date| each_date <= repeats_until }
  end

  def display_name
    name.presence || I18n.t("debt_plans.extra_payment.default_name")
  end

  private
    def repeats_after_date
      errors.add(:repeats_until, :invalid) if repeats_until.present? && date.present? && repeats_until < date
    end
end
