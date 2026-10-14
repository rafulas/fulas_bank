# Fulas Bank: the user marks a movement as fixed, recurring or variable (see
# Transaction::ExpenseClassifiable).
#
# Fixed and recurring movements repeat, so they need a recurring series for
# the forecast to project them:
#   - if the movement already pays one, that one is used;
#   - if not, one is created from the movement, as "Mark as recurring" does.
# Fixed means it never ends; recurring means it ends on a date, given either
# as the date itself or as the number of payments still to come. The end is
# kept on the series, where the forecast and the Bills pages read it.
#
# Marking a movement variable does not touch its series: the user may still
# want the bill tracked, and archiving it stays a decision of the Bills page.
class Transaction::ExpenseTypeChange
  MAX_PERIODS = RecurringTransaction::MAX_END_AFTER_COUNT

  attr_reader :transaction, :expense_type, :end_on, :periods, :today, :error

  def initialize(transaction, expense_type:, end_on: nil, periods: nil, today: Date.current)
    @transaction = transaction
    @expense_type = expense_type.to_s
    @end_on = parse_date(end_on)
    @periods = periods.presence&.to_i
    @today = today
  end

  # @return [Boolean] whether the change was saved; #error says why not
  def save
    return fail_with(:invalid_type) unless Transaction::ExpenseClassifiable::EXPENSE_TYPES.include?(expense_type)
    return fail_with(:transfer) if transaction.transfer?

    if expense_type == "recurring"
      return fail_with(:end_required) if end_on.nil? && periods.nil?
      return fail_with(:invalid_periods) if periods && !periods.between?(1, MAX_PERIODS)
    end

    series = expense_type == "variable" ? nil : find_or_create_series
    return fail_with(:series_failed) if expense_type != "variable" && series.nil?

    Transaction.transaction do
      transaction.update!(expense_type: expense_type)
      apply_end(series) if series
    end

    true
  rescue ActiveRecord::RecordInvalid
    fail_with(:invalid)
  end

  private
    def fail_with(reason)
      @error = reason
      false
    end

    def parse_date(value)
      return value if value.is_a?(Date)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    # A savepoint of its own: on PostgreSQL a failed insert aborts the whole
    # surrounding transaction, and a duplicate series is an expected outcome.
    def find_or_create_series
      transaction.recurring_series || RecurringTransaction.transaction(requires_new: true) do
        RecurringTransaction.create_from_transaction(transaction)
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      transaction.existing_manual_recurring_transaction
    end

    def apply_end(series)
      series.status = "active" unless series.active? || series.paused?
      # Without an end first, so the schedule can count the payments to come.
      series.end_after_count = nil
      series.end_mode = "never"
      series.end_on = nil

      if expense_type == "recurring"
        last_date = end_on || last_payment_date(series)
        series.end_mode = "on_date"
        series.end_on = last_date
      end

      series.save! if series.changed?
    end

    # The date of the last of the next `periods` payments, read from the
    # series' own schedule (with no end yet, so it can run that far).
    def last_payment_date(series)
      schedule = series.schedule
      date = today

      periods.times do
        following = schedule.first_occurrence_after(date)
        break unless following

        date = following
      end

      date
    end
end
