# A bank movement recorded as the payment of one of a loan's instalments.
#
# The movement stays where the bank import put it -- in the account it was paid
# from -- so the money is counted once. The link is what makes it show on the
# loan's page, beside the instalment the schedule expected for that month.
class Loan::PaymentLink < ApplicationRecord
  self.table_name = "loan_payment_links"

  belongs_to :loan
  belongs_to :entry

  validates :entry_id, uniqueness: true
  validate :entry_is_an_outgoing_transaction
  validate :entry_belongs_to_loan_family

  scope :reverse_chronological, -> { joins(:entry).order("entries.date DESC, entries.created_at DESC") }

  # The instalment the schedule expected in the month this movement was paid,
  # or nil when the loan has no schedule or none falls in that month.
  def scheduled_payment
    loan.amortization_schedule&.payment_for(entry.date)
  end

  private
    def entry_is_an_outgoing_transaction
      return if entry.blank?
      return if entry.entryable_type == "Transaction" && entry.amount.positive?

      errors.add(:entry, :invalid)
    end

    def entry_belongs_to_loan_family
      return if entry.blank? || loan.blank?

      loan_account = loan.account
      return if loan_account.present? && entry.account.family_id == loan_account.family_id && entry.account_id != loan_account.id

      errors.add(:entry, :invalid)
    end
end
