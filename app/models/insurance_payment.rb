# Fulas Bank: one instalment of an insurance paid in custom instalments (see
# Insurance#installments), on the day it is due, and how it was paid: by a
# bank charge (entry), or marked paid by hand when there is no charge to
# point at (paid in cash, or before the statements in the app).
#
# The app proposes the charge on its own (InsuranceLinker): it stays
# `suggested` until the user confirms it. A charge turned down is kept in
# rejected_entry_ids so it is not proposed again for this instalment.
#
# A row exists only for instalments something happened to; the rest are
# simply not paid yet.
class InsurancePayment < ApplicationRecord
  belongs_to :insurance
  belongs_to :entry, optional: true

  validates :due_on, presence: true, uniqueness: { scope: :insurance_id }
  validates :entry_id, uniqueness: true, allow_nil: true
  validate :entry_is_a_charge_of_the_family

  scope :suggested, -> { where(suggested: true) }

  def paid?
    paid_manually? || (entry_id.present? && !suggested?)
  end

  def reject_entry!
    return if entry_id.nil?

    update!(rejected_entry_ids: (Array(rejected_entry_ids) | [ entry_id ]), entry: nil, suggested: false)
  end

  private
    def entry_is_a_charge_of_the_family
      return if entry.nil?
      return if entry.transaction? && entry.amount.to_d.positive? && entry.account.family_id == insurance&.family_id

      errors.add(:entry, :invalid)
    end
end
