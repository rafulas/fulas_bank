# A record that can be tied to the bank charge that paid for it: a vehicle's
# logbook line (Vehicle::Log) or a property's expense (Property::Expense).
#
# The money is recorded once, by the bank import; the record adds what the
# bank does not know (odometer, litres, which renovation...).
#
# A link can be proposed by the app (AssetLinker) and wait for the user:
#   - suggestion "link": an existing record was matched with a charge.
#   - suggestion "new":  the record itself was created from the charge.
# Confirming clears the mark. Rejecting undoes the link (or deletes the record
# the app created) and remembers the charge, so it is not proposed again for
# the same account.
module BankChargeLinkable
  extend ActiveSupport::Concern

  SUGGESTIONS = %w[link new].freeze

  # Bank charges up to this many days either side of the record's date are
  # offered as its payment, closest amount first.
  MATCH_WINDOW = 15.days
  MATCH_LIMIT = 15

  included do
    belongs_to :entry, optional: true

    validates :suggestion, inclusion: { in: SUGGESTIONS }, allow_nil: true
    validates :entry_id, uniqueness: true, allow_nil: true
    validate :entry_belongs_to_family
    validate :entry_not_linked_elsewhere

    # Records the app created from a charge and the user has not confirmed:
    # they stay out of totals until confirmed.
    scope :pending, -> { where(suggestion: "new") }
    scope :settled, -> { where(suggestion: nil).or(where(suggestion: "link")) }
    scope :suggested, -> { where.not(suggestion: nil) }
  end

  # Every model whose records link a bank charge.
  def self.linkable_models
    [ Vehicle::Log, Property::Expense ]
  end

  # The vehicle or property account the record belongs to.
  def asset_account
    raise NotImplementedError
  end

  def family
    asset_account.family
  end

  def suggested?
    suggestion.present?
  end

  def pending?
    suggestion == "new"
  end

  def confirm_link!
    update!(suggestion: nil)
  end

  # Turns the proposal down: the charge is remembered as not belonging to this
  # account, and the link (or the record the app created for it) goes away.
  def reject_link!
    transaction do
      if entry_id.present?
        AssetLinkRejection.find_or_create_by!(entry_id: entry_id, account_id: asset_account.id)
      end

      if pending?
        destroy!
      else
        update!(entry: nil, suggestion: nil)
      end
    end
  end

  # Outgoing purchases of the family around this record's date that are not
  # already linked to another record: closest amount first (when the record
  # has one), then closest date.
  def candidate_entries(scope: family.entries, limit: MATCH_LIMIT)
    return [] if date.blank?

    candidates = scope.where(entryable_type: "Transaction", entryable_id: candidate_transactions, excluded: false)
                      .where(date: (date - MATCH_WINDOW)..(date + MATCH_WINDOW))
                      .where("entries.amount > 0")
                      .where.not(id: AssetLink.linked_entry_ids(except: self))
                      .includes(:account)
                      .order(date: :desc)
                      .limit(200)
                      .to_a

    target = amount.to_d
    candidates.sort_by do |entry|
      amount_gap = target.positive? ? ((entry.amount - target).abs / target) : 0
      [ amount_gap, (entry.date - date).abs ]
    end.first(limit)
  end

  private
    # Purchases only: transfers between the family's own accounts (paying off
    # the card, moving savings) are never a cost of the asset. Property
    # expenses also accept loan payments, for the mortgage.
    def candidate_transactions
      Transaction.where.not(kind: Transaction::TRANSFER_KINDS)
                 .where.not(id: Transfer.select(:outflow_transaction_id))
                 .select(:id)
    end

    def take_amount_from_entry
      return if entry.blank? || amount.to_d.positive?

      self.amount = entry.amount.abs
    end

    def entry_belongs_to_family
      return if entry.blank? || asset_account.blank?
      return if entry.account.family_id == asset_account.family_id

      errors.add(:entry, :invalid)
    end

    # A charge pays for one thing: a refuel or a renovation, not both.
    def entry_not_linked_elsewhere
      return if entry_id.blank?

      others = BankChargeLinkable.linkable_models - [ self.class ]
      errors.add(:entry, :taken) if others.any? { |model| model.exists?(entry_id: entry_id) }
    end
end
