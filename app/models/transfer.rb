class Transfer < ApplicationRecord
  belongs_to :inflow_transaction, class_name: "Transaction"
  belongs_to :outflow_transaction, class_name: "Transaction"

  has_many :fee_transactions, class_name: "Transaction", dependent: :destroy

  attr_accessor :source_fee_amount, :destination_fee_amount, :tag_ids

  enum :status, { pending: "pending", confirmed: "confirmed" }

  validates :inflow_transaction_id, uniqueness: true
  validates :outflow_transaction_id, uniqueness: true

  validate :transfer_has_different_accounts
  validate :transfer_has_opposite_amounts
  validate :transfer_within_date_range
  validate :transfer_has_same_family

  # Accounts whose money is invested: selling from one of them into any other
  # account is income (see Transaction::INVESTMENT_WITHDRAWAL_IDS_SQL).
  INVESTMENT_ACCOUNT_TYPES = %w[Investment Crypto].freeze

  after_create :categorize_investment_withdrawal

  class << self
    def kind_for_account(account)
      if account.loan?
        "loan_payment"
      elsif account.credit_card?
        "cc_payment"
      elsif account.investment? || account.crypto?
        "investment_contribution"
      elsif account.liability?
        "cc_payment"
      else
        "funds_movement"
      end
    end
  end

  def has_source_fee?
    derived_source_fee_amount > 0
  end

  def has_destination_fee?
    derived_destination_fee_amount > 0
  end

  def has_fees?
    has_source_fee? || has_destination_fee?
  end

  def total_fee
    derived_source_fee_amount + derived_destination_fee_amount
  end

  def derived_source_fee_amount
    fee_transactions.joins(:entry).where(entries: { account_id: from_account.id }).sum("entries.amount")
  end

  def derived_destination_fee_amount
    fee_transactions.joins(:entry).where(entries: { account_id: to_account.id }).sum("entries.amount")
  end

  def amount_abs
    inflow_transaction&.entry&.amount_money&.abs || Money.new(0, from_account&.currency || "USD")
  end

  def name
    acc = to_account
    if payment?
      acc ? "Payment to #{acc.name}" : "Payment"
    else
      acc ? "Transfer to #{acc.name}" : "Transfer"
    end
  end

  def payment?
    to_account&.liability?
  end

  def loan_payment?
    outflow_transaction&.kind == "loan_payment"
  end

  def liability_payment?
    outflow_transaction&.kind == "cc_payment"
  end

  def regular_transfer?
    outflow_transaction&.kind == "funds_movement"
  end

  def transfer_type
    return "loan_payment" if loan_payment?
    return "liability_payment" if liability_payment?
    "transfer"
  end

  def categorizable?
    to_account&.accountable_type == "Loan"
  end

  def reject!
    Transfer.transaction do
      RejectedTransfer.find_or_create_by!(inflow_transaction_id: inflow_transaction_id, outflow_transaction_id: outflow_transaction_id)
      destroy!
    end
  end

  def destroy!
    Transfer.transaction do
      [ inflow_transaction, outflow_transaction ].each do |transaction|
        next if transaction.nil?
        next unless Transaction.exists?(transaction.id)
        begin
          transaction.update!(kind: "standard")
          # The entry survives this destroy (only the Transfer join row and
          # fee transactions go away), but its idempotency_key must not: a
          # later retry of the original create request looks up that key,
          # finds no Transfer anymore, and would otherwise hit the unique
          # index on the stale entry and raise instead of creating a new
          # transfer (see Transfer::Creator#find_existing_transfer).
          transaction.entry.update!(idempotency_key: nil) if transaction.entry&.idempotency_key.present?
        rescue ActiveRecord::RecordNotFound
        rescue NoMethodError
          next
        end
      end
      super
    end
  end

  def confirm!
    update!(status: "confirmed")
  end

  def date
    inflow_transaction&.entry&.date
  end

  def sync_account_later
    inflow_transaction&.entry&.sync_account_later
    outflow_transaction&.entry&.sync_account_later
    fee_transactions.each { |t| t.entry&.sync_account_later }
  end

  def to_account
    inflow_transaction&.entry&.account
  end

  def from_account
    outflow_transaction&.entry&.account
  end

  private
    def transfer_has_different_accounts
      return unless inflow_transaction&.entry && outflow_transaction&.entry
      errors.add(:base, :different_accounts) if to_account == from_account
    end

    def transfer_has_same_family
      return unless inflow_transaction&.entry && outflow_transaction&.entry
      errors.add(:base, :same_family) unless to_account&.family == from_account&.family
    end

    def transfer_has_opposite_amounts
      return unless inflow_transaction&.entry && outflow_transaction&.entry

      inflow_entry = inflow_transaction.entry
      outflow_entry = outflow_transaction.entry

      inflow_amount_raw = inflow_entry.amount
      outflow_amount_raw = outflow_entry.amount

      errors.add(:base, :opposite_amounts) unless inflow_amount_raw.negative? && outflow_amount_raw.positive?

      if inflow_entry.currency == outflow_entry.currency
        errors.add(:base, :opposite_amounts) if inflow_amount_raw + outflow_amount_raw != 0
      end
    end

    def transfer_within_date_range
      return unless inflow_transaction&.entry && outflow_transaction&.entry

      date_diff = (inflow_transaction.entry.date - outflow_transaction.entry.date).abs
      max_days = status == "confirmed" ? 30 : 4
      errors.add(:base, :within_days, count: max_days) if date_diff > max_days
    end

    # Fulas Bank: the cash from selling an investment counts as income (see
    # Transaction::INVESTMENT_WITHDRAWAL_IDS_SQL), so, mirror of a
    # contribution, it goes to "Inversiones financieras" when it has no
    # category and the family has the default categories.
    #
    # The accounts are read with a query rather than through each leg's
    # entry: a transfer can be created before its entries (they are added
    # right after), and reading the association here would cache it empty.
    def categorize_investment_withdrawal
      return if inflow_transaction.nil? || inflow_transaction.category_id.present?

      legs = Entry.where(entryable_type: "Transaction", entryable_id: [ outflow_transaction_id, inflow_transaction_id ])
                  .joins(:account)
                  .pluck(:entryable_id, "accounts.accountable_type", "accounts.family_id")
                  .index_by(&:first)
      from = legs[outflow_transaction_id]
      to = legs[inflow_transaction_id]
      return if from.nil? || to.nil?
      return unless INVESTMENT_ACCOUNT_TYPES.include?(from[1]) && INVESTMENT_ACCOUNT_TYPES.exclude?(to[1])

      category = Category.find_by(family_id: to[2], name: Category::FulasTree::INVESTMENT_CONTRIBUTIONS_NAME)
      inflow_transaction.update!(category: category) if category
    end
end
