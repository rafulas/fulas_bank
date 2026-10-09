# A cost of a property: a renovation, the home insurance, a mortgage payment,
# the community fees, the property tax...
#
# Like a vehicle's logbook line, it is tied to the bank charge that paid for it
# (`entry`, see BankChargeLinkable), so the money is counted once, by the bank
# import, and the property keeps the list of what it has cost.
class Property::Expense < ApplicationRecord
  include Monetizable, BankChargeLinkable

  KINDS = %w[mortgage insurance renovation maintenance community tax utilities furniture other].freeze

  # Scanned invoices and receipts: same formats and limits as a transaction's.
  MAX_ATTACHMENTS = Transaction::MAX_ATTACHMENTS_PER_TRANSACTION
  MAX_ATTACHMENT_SIZE = Transaction::MAX_ATTACHMENT_SIZE
  ATTACHMENT_TYPES = Transaction::ALLOWED_CONTENT_TYPES

  monetize :amount

  has_many_attached :attachments

  belongs_to :property

  validates :kind, inclusion: { in: KINDS }
  validates :date, :currency, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validate :attachments_are_acceptable, if: -> { attachments.attached? }

  before_validation :inherit_currency
  before_validation :take_amount_from_entry

  scope :chronological, -> { order(:date, :created_at) }
  scope :reverse_chronological, -> { order(date: :desc, created_at: :desc) }

  def asset_account
    property&.account
  end

  private
    # The mortgage is usually paid as a loan payment (a transfer to the loan
    # account), so loan payments are offered too.
    def candidate_transactions
      purchases = Transaction.where.not(kind: Transaction::TRANSFER_KINDS)
                             .where.not(id: Transfer.select(:outflow_transaction_id))

      purchases.or(Transaction.where(kind: "loan_payment")).select(:id)
    end

    def inherit_currency
      self.currency ||= property&.account&.currency
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
