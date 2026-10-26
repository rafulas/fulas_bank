# Fulas Bank: links a movement to one recurring series (fixed, bill or
# subscription; see RecurringTransaction::Kind), from the movement's detail,
# like the car's charges. It began with subscriptions only, hence the name.
#
# It is also how a payment the app did not recognise gets its series: the
# bank writes «Préstamo RRHH Reforma» and the series is called «Préstamo
# Reforma Vivienda», so the matcher leaves it alone until the user links it.
#
# Two charges from the same shop can be two subscriptions (Apple Music at
# 10,99 € and iCloud 2 TB at 2,99 €): each is its own series, and the app's
# matcher tells them apart by amount. When it gets one wrong, the user picks
# the right one here and the app remembers it:
#   - the movement leaves the series it was in, which will not propose it
#     again (RecurringMatchRejection);
#   - it pays the target series' payment closest to its date (created if the
#     series had none stored that far back), and the series learns from it.
class SubscriptionLink
  WINDOW_DAYS = 20

  attr_reader :entry, :family

  def initialize(entry)
    @entry = entry
    @family = entry.account.family
  end

  # The series the movement pays, if any.
  def current
    allocations.map { |allocation| allocation.recurring_occurrence.recurring_transaction }.first
  end

  # The family's active series the movement could pay: an income with the
  # incomes, a charge with the charges. Fixed first, then bills and
  # subscriptions, each by name.
  def options
    income = entry.amount.negative?
    family.recurring_transactions.active.includes(:merchant).to_a
          .select { |series| series.amount.to_d.negative? == income }
          .sort_by { |series| [ RecurringTransaction::Kind::KINDS.index(series.fulas_kind), series.display_name.to_s.downcase ] }
  end

  # Moves the movement to `series` (nil: to none).
  def link!(series)
    RecurringAllocation.transaction do
      release_current!
      next unless series

      RecurringMatchRejection.where(recurring_transaction: series, entry: entry).delete_all
      RecurringTransaction::Allocator.new(occurrence_for(series)).allocate!(entry: entry, source: "user_confirmed", paid_on: entry.date)
    end
    true
  end

  # A new series made from the movement, of `kind` (by default the one its
  # name and category suggest), and the movement linked to it.
  def create!(name: nil, kind: "subscription")
    series = RecurringTransaction.transaction(requires_new: true) do
      RecurringTransaction.create_from_transaction(entry.transaction)
    end
    kind = RecurringTransaction::Kind::KINDS.include?(kind.to_s) ? kind.to_s : RecurringTransaction::Kind.guess(series)
    series.update!(bill_type: RecurringTransaction::Kind.bill_type_for(kind, series), name: name.presence || series.name)
    link!(series)
    series
  end

  private
    def allocations
      entry.recurring_allocations.includes(recurring_occurrence: :recurring_transaction).to_a
    end

    def release_current!
      allocations.each do |allocation|
        occurrence = allocation.recurring_occurrence
        RecurringMatchRejection.find_or_create_by!(recurring_transaction: occurrence.recurring_transaction, entry: entry)
        RecurringTransaction::Allocator.new(occurrence).unallocate!(allocation)
      end
    end

    # The series' payment due closest to the movement, preferring one still
    # open; stored ones first, else the schedule's around that date.
    def occurrence_for(series)
      range = (entry.date - WINDOW_DAYS)..(entry.date + WINDOW_DAYS)
      RecurringTransaction::OccurrenceGenerator.new(series).backfill!(from: range.begin, through: range.end)

      candidates = series.recurring_occurrences.where(due_on: range).to_a
      candidates.min_by { |occurrence| [ occurrence.scheduled? ? 0 : 1, (occurrence.due_on - entry.date).abs ] } ||
        raise(ActiveRecord::RecordNotFound, "no payment of #{series.display_name} near #{entry.date}")
    end
end
