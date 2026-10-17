require "test_helper"

class RecurringAssignmentTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
  end

  def payslips(count = 3)
    count.times.map do |index|
      create_transaction(account: @account, name: "NOMINA EMPRESA", amount: -2_000, date: (Date.current - 15).prev_month(index))
    end
  end

  def paid_by(series)
    RecurringAllocation.joins(:recurring_occurrence).where(recurring_occurrences: { recurring_transaction_id: series.id }).pluck(:entry_id)
  end

  test "creates a new monthly series with its name and makes every payslip one of its payments" do
    entries = payslips

    assignment = RecurringAssignment.new(family: @family, entries: entries, series_id: "new", name: "Nómina Rafa BBVA", frequency: "monthly")

    assert_equal 3, assignment.apply!
    series = assignment.series
    assert_equal "Nómina Rafa BBVA", series.name
    assert_equal "income", series.bill_type
    assert_equal "monthly", RecurringTransaction::FrequencyPreset.detect(series).key
    assert_equal entries.map(&:id).sort, paid_by(series).sort
  end

  test "adds the movements to an existing series, and skips transfers" do
    series = RecurringAssignment.new(family: @family, entries: payslips(1), series_id: "new", name: "Nómina").tap(&:apply!).series
    more = payslips(3).drop(1)
    transfer = create_transfer(from_account: @account, to_account: accounts(:investment), amount: 100, date: Date.current - 2).outflow_transaction.entry

    count = RecurringAssignment.new(family: @family, entries: more + [ transfer ], series_id: series.id).apply!

    assert_equal 2, count
    assert_not_includes paid_by(series), transfer.id
  end

  test "the frequency list sets the series' schedule" do
    entry = create_transaction(account: @account, name: "Limpieza", amount: 60, date: Date.current - 3)

    series = RecurringAssignment.new(family: @family, entries: [ entry ], series_id: "new", frequency: "every_2_weeks").tap(&:apply!).series
    assert_equal "biweekly", RecurringTransaction::FrequencyPreset.detect(series).key

    other = create_transaction(account: @account, name: "Gestoría", amount: 90, date: Date.current - 3)
    series = RecurringAssignment.new(family: @family, entries: [ other ], series_id: "new", frequency: "every_3_months").tap(&:apply!).series
    assert_equal "quarterly", RecurringTransaction::FrequencyPreset.detect(series).key
  end
end
