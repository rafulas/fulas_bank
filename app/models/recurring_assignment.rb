# Fulas Bank: "Añadir a recurrente", as in Bilance. One or several movements
# (all the payslips found with a filter, say) become payments of one
# recurring series in one go:
#
#   - an existing series, chosen from the list; or
#   - a new one, made from the newest movement, with the name and the
#     frequency the user picks ("Mensualmente", "Cada 2 semanas"...).
#
# Each movement pays the series' payment closest to its date, as when it is
# linked from its own detail (SubscriptionLink): it leaves any other series it
# paid, and the series learns its amounts from them. Transfers are skipped:
# they are not a bill or an income.
class RecurringAssignment
  NEW = "new".freeze

  # The frequencies of Bilance's list, in its order, and the schedule each
  # one is (see RecurringTransaction::FrequencyPreset).
  FREQUENCIES = {
    "weekly" => { preset: "weekly" },
    "every_2_weeks" => { preset: "biweekly" },
    "every_3_weeks" => { preset: "interval", interval: 3, interval_unit: "weekly" },
    "every_4_weeks" => { preset: "interval", interval: 4, interval_unit: "weekly" },
    "every_5_weeks" => { preset: "interval", interval: 5, interval_unit: "weekly" },
    "every_6_weeks" => { preset: "interval", interval: 6, interval_unit: "weekly" },
    "monthly" => { preset: "monthly" },
    "every_2_months" => { preset: "interval", interval: 2, interval_unit: "monthly" },
    "every_3_months" => { preset: "quarterly" },
    "every_6_months" => { preset: "semiannual" },
    "yearly" => { preset: "annual" }
  }.freeze
  DEFAULT_FREQUENCY = "monthly".freeze

  attr_reader :family, :entries, :series_id, :name, :frequency, :series, :skipped

  def initialize(family:, entries:, series_id:, name: nil, frequency: nil)
    @family = family
    @entries = entries.to_a
    @series_id = series_id.to_s
    @name = name.to_s.strip.presence
    @frequency = FREQUENCIES.key?(frequency.to_s) ? frequency.to_s : DEFAULT_FREQUENCY
    @skipped = 0
  end

  # The movements that can be a series' payment, oldest first.
  def movements
    @movements ||= entries.select { |entry| entry.transaction? && !entry.transaction.transfer? }.sort_by(&:date)
  end

  def new_series?
    series_id == NEW
  end

  # @return [Integer] how many movements now pay the series
  def apply!
    return 0 if movements.empty?

    @series = new_series? ? create_series! : family.recurring_transactions.find(series_id)

    movements.count do |entry|
      next true if pays?(entry, series)

      SubscriptionLink.new(entry).link!(series)
      true
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid, RecurringTransaction::Allocator::OverAllocationError
      # No payment of the series near that date (a weekly series and a
      # movement far from its days), or that payment is already covered.
      @skipped += 1
      false
    end
  end

  private
    # From the newest movement: its account, amount and day; income or bill
    # by its sign. With the same shop and amount as an existing manual
    # series, that one is used.
    def create_series!
      newest = movements.last

      series = begin
        RecurringTransaction.transaction(requires_new: true) do
          RecurringTransaction.create_from_transaction(newest.transaction)
        end
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        newest.transaction.existing_manual_recurring_transaction || raise
      end

      series.name = name if name
      options = FREQUENCIES.fetch(frequency)
      RecurringTransaction::FrequencyPreset.apply(
        series, preset: options[:preset], interval: options[:interval], interval_unit: options[:interval_unit],
        weekday: newest.date.wday, day_of_month: newest.date.day, month_of_year: newest.date.month
      )
      series.save!
      series
    end

    def pays?(entry, series)
      entry.recurring_allocations
           .joins(:recurring_occurrence)
           .where(recurring_occurrences: { recurring_transaction_id: series.id })
           .exists?
    end
end
