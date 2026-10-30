# Fulas Bank: what the bulk edit drawer can change about several movements
# besides their name, category, tags... (see Entry.bulk_update!):
#
#   - recurring: "new" makes one recurring series from the newest of them and
#     links them all to it, as payments of that series; the id of an existing
#     series links them to that one. A movement that paid another series
#     leaves it, as when it is moved from its own detail (SubscriptionLink).
#   - expense_type: fixed, recurring (with `end_on`, the last payment) or
#     variable, for each movement (Transaction::ExpenseTypeChange). With a
#     series chosen too, the series is linked first, so the type applies to
#     that series rather than one made per movement.
#   - excluded: "1" leaves them out of reports and budgets, "0" puts them back.
#   - one_time: "1" marks them as one-off (puntual), "0" back to ordinary.
#   - add_tag_ids / remove_tag_ids: tags put on or taken off each movement,
#     keeping its other tags.
#   - loan_account_id: each outgoing movement linked as a payment of that
#     loan (one already linked to a loan is left as it is).
#
# Transfers are skipped for the first two: they are not a bill or a cost.
class Transaction::BulkClassification
  attr_reader :family, :entries, :recurring, :expense_type, :end_on, :excluded, :one_time, :add_tag_ids, :remove_tag_ids, :loan_account_id

  def initialize(family:, entries:, recurring: nil, expense_type: nil, end_on: nil, excluded: nil,
                 one_time: nil, add_tag_ids: nil, remove_tag_ids: nil, loan_account_id: nil)
    @family = family
    @entries = entries.to_a
    @recurring = recurring.presence
    @expense_type = expense_type.presence
    @end_on = end_on.presence
    @excluded = excluded.presence
    @one_time = one_time.presence
    @add_tag_ids = family.tags.where(id: Array(add_tag_ids).compact_blank).pluck(:id)
    @remove_tag_ids = family.tags.where(id: Array(remove_tag_ids).compact_blank).pluck(:id)
    @loan_account_id = loan_account_id.presence
  end

  def any_change?
    recurring || expense_type || excluded || one_time || add_tag_ids.any? || remove_tag_ids.any? || loan_account_id
  end

  # @return [Integer] how many movements changed
  def apply!
    return 0 unless any_change?

    changed = Set.new

    Entry.transaction do
      if excluded
        entries.each do |entry|
          entry.update!(excluded: excluded == "1")
          changed << entry.id
        end
      end

      if recurring && (series = target_series)
        movements.each do |entry|
          next if pays?(entry, series)

          SubscriptionLink.new(entry).link!(series)
          changed << entry.id
        end
      end

      if expense_type
        movements.each do |entry|
          change = Transaction::ExpenseTypeChange.new(Transaction.find(entry.entryable_id), expense_type: expense_type, end_on: end_on)
          changed << entry.id if change.save
        end
      end

      if one_time
        kind = one_time == "1" ? "one_time" : "standard"
        movements.each do |entry|
          transaction = Transaction.find(entry.entryable_id)
          next if transaction.kind == kind || !%w[standard one_time].include?(transaction.kind)

          transaction.update!(kind: kind)
          changed << entry.id
        end
      end

      if add_tag_ids.any? || remove_tag_ids.any?
        entries.select(&:transaction?).each do |entry|
          transaction = Transaction.find(entry.entryable_id)
          tags = (transaction.tag_ids | add_tag_ids) - remove_tag_ids
          next if tags.sort == transaction.tag_ids.sort

          transaction.tag_ids = tags
          transaction.lock_attr!(:tag_ids)
          changed << entry.id
        end
      end

      if (loan = target_loan)
        movements.each do |entry|
          next unless entry.amount.positive? && !Loan::PaymentLink.exists?(entry_id: entry.id)

          loan.link_payment!(entry)
          changed << entry.id
        end
      end
    end

    changed.size
  end

  private
    # The transactions that can be a bill's payment: not transfers.
    def movements
      @movements ||= entries.select { |entry| entry.transaction? && !entry.transaction.transfer? }
    end

    def target_series
      return existing_series unless recurring == "new"
      return if movements.empty?

      newest = movements.max_by(&:date)
      RecurringTransaction.transaction(requires_new: true) do
        RecurringTransaction.create_from_transaction(newest.transaction)
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      newest.transaction.existing_manual_recurring_transaction
    end

    def target_loan
      return unless loan_account_id

      family.accounts.find_by(id: loan_account_id, accountable_type: "Loan")&.loan
    end

    def existing_series
      family.recurring_transactions.find_by(id: recurring)
    end

    def pays?(entry, series)
      entry.recurring_allocations
           .joins(:recurring_occurrence)
           .where(recurring_occurrences: { recurring_transaction_id: series.id })
           .exists?
    end
end
