# Fulas Bank: the user says what kind of movement this is: variable, fixed,
# a bill or a subscription (see Transaction::ExpenseClassifiable and
# RecurringTransaction::Kind).
#
# A fixed one, a bill or a subscription repeats, so it needs a recurring
# series for the forecast to project it:
#   - if the movement already pays one, that one is used;
#   - if not, one is created from the movement, as "Mark as recurring" does.
# The series takes the kind chosen. A fixed one may end (a loan): on a date,
# given as the date itself or as the number of payments still to come, or
# never. The end is kept on the series, where the forecast and Planes read
# it. "recurring", the old name of a fixed one that ends, is still taken.
#
# Marking a movement variable does not touch its series: the user may still
# want the bill tracked, and archiving it stays a decision of the Bills page.
class Transaction::ExpenseTypeChange
  MAX_PERIODS = RecurringTransaction::MAX_END_AFTER_COUNT
  # What the user chooses, in the order offered.
  CHOICES = (%w[variable] + RecurringTransaction::Kind::KINDS).freeze

  attr_reader :transaction, :expense_type, :end_on, :periods, :never_ends, :today, :error

  # `never_ends` clears the end of a fixed one; without it, nor a date nor a
  # number of payments, its end is left as it is.
  def initialize(transaction, expense_type:, end_on: nil, periods: nil, never_ends: false, today: Date.current)
    @transaction = transaction
    @expense_type = expense_type.to_s
    @end_on = parse_date(end_on)
    @periods = periods.presence&.to_i
    @never_ends = never_ends
    @today = today
  end

  # What a movement is, as offered in CHOICES: variable, or its series' kind.
  def self.current_choice(transaction)
    return "variable" if transaction.effective_expense_type == "variable"

    transaction.recurring_series&.fulas_kind || "fixed"
  end

  # @return [Boolean] whether the change was saved; #error says why not
  def save
    return fail_with(:invalid_type) unless (CHOICES + %w[recurring]).include?(expense_type)
    return fail_with(:transfer) if transaction.transfer?
    return fail_with(:end_required) if expense_type == "recurring" && end_on.nil? && periods.nil?
    return fail_with(:invalid_periods) if periods && !periods.between?(1, MAX_PERIODS)

    series = variable? ? nil : find_or_create_series
    return fail_with(:series_failed) if !variable? && series.nil?

    Transaction.transaction do
      transaction.update!(expense_type: variable? ? "variable" : "fixed")
      apply_kind(series) if series
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

    def variable?
      expense_type == "variable"
    end

    # The kind the series takes: "recurring" was a fixed one that ends.
    def kind
      expense_type == "recurring" ? "fixed" : expense_type
    end

    def apply_kind(series)
      series.status = "active" unless series.active? || series.paused?
      series.fulas_kind = kind
      apply_end(series)

      series.save! if series.changed?
    end

    # Only a fixed one ends; a bill or a subscription is switched off
    # instead. A fixed one without an end given keeps the one it had.
    def apply_end(series)
      clear = kind != "fixed" || never_ends || end_on || periods
      return unless clear

      # Without an end first, so the schedule can count the payments to come.
      series.end_after_count = nil
      series.end_mode = "never"
      series.end_on = nil
      return unless kind == "fixed" && (end_on || periods)

      series.end_mode = "on_date"
      series.end_on = end_on || last_payment_date(series)
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
