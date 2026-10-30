class RecurringTransaction
  # Materializes Schedule output into recurring_occurrences rows. An idempotent
  # upsert keyed on (series, original_due_on), so re-running only adds missing
  # rows and never duplicates or touches existing ones.
  #
  # Only scheduled, allocation-free, not-yet-due rows are ever deleted. Anything
  # closed or carrying a payment is immutable history.
  class OccurrenceGenerator
    HORIZON_DAYS = 90

    attr_reader :series

    def initialize(series)
      @series = series
    end

    # From the start of the current cycle, so a recently-due unpaid occurrence
    # exists and not just future ones, through a horizon always extended far
    # enough to include the next occurrence even on annual cadences.
    def generate!(through: nil)
      return 0 unless series.active?

      schedule = series.schedule
      from = schedule.cycle_for(Date.current)&.begin || Date.current

      # A declared bill's anchor is its first obligation, so the cycle lookback
      # must not fabricate a previous-cycle debt. Auto-detected series keep the
      # cycle start, since their history predates the row.
      from = [ from, series.anchor_date ].compact.max if series.manual?

      through ||= default_horizon(schedule)

      prune_past_end!
      upsert_window(from, through)
    end

    # After a schedule edit: drop the re-generatable future and rebuild it under
    # the new rules. Rows with payments or closed state are kept as they were.
    def regenerate_future!(through: nil)
      series.recurring_occurrences
            .open_status
            .where("due_on >= ?", Date.current)
            .where.not(id: RecurringAllocation.select(:recurring_occurrence_id))
            .delete_all
      prune_past_end!

      generate!(through: through)
    end

    # Fulas Bank: unpaid rows dated after the series' end date. An end date set
    # after a payment had already fallen due (a rent ended in June, edited in
    # October) left that month showing as overdue in Planes. Rows carrying a
    # payment are history and stay.
    def prune_past_end!
      return 0 unless series.ends_on_date? && series.end_on.present?

      series.recurring_occurrences
            .open_status
            .where("due_on > ?", series.end_on)
            .where.not(id: RecurringAllocation.select(:recurring_occurrence_id))
            .delete_all
    end

    # Materializes a past window (catch-up/backfill). The caller decides what
    # happens to uncovered past occurrences; this only creates rows.
    def backfill!(from:, through: Date.current)
      return 0 unless series.active?

      upsert_window(from, through)
    end

    private
      def default_horizon(schedule)
        horizon = Date.current + HORIZON_DAYS
        next_due = schedule.first_occurrence_after(Date.current)

        # A finite plan materializes whole: an installment run is bounded by
        # definition, and seeing all N payments (and the end) is the point.
        if series.ends_after_count? && series.end_after_count.present?
          cycle_days = (365.25 / schedule.occurrences_per_year).ceil
          plan_end = (series.anchor_date || Date.current) + cycle_days * (series.end_after_count + 1)
          return [ horizon, next_due, plan_end ].compact.max
        end

        [ horizon, next_due ].compact.max
      end

      def upsert_window(from, through)
        pairs = series.schedule.occurrence_pairs_between(from, through)
        return 0 if pairs.empty?

        now = Time.current
        rows = pairs.map do |pair|
          {
            recurring_transaction_id: series.id,
            family_id: series.family_id,
            original_due_on: pair.original_due_on,
            due_on: pair.due_on,
            currency: series.currency,
            status: "scheduled",
            created_at: now,
            updated_at: now
          }
        end

        result = RecurringOccurrence.insert_all(rows, unique_by: "idx_recurring_occurrences_identity")
        result.rows.size
      end
  end
end
