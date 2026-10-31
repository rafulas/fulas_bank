require "test_helper"

class Import::RowTest < ActiveSupport::TestCase
  test "reads the time written after the date, as Bilance exports it" do
    assert_equal "15:30", Import::Row.new(date: "2026-10-19 15:30:00.000").time_of_day
    assert_equal "08:05", Import::Row.new(date: "19/10/2026 8:05").time_of_day
    assert_nil Import::Row.new(date: "2026-10-19 00:00:00.000").time_of_day, "midnight is the same as no time"
    assert_nil Import::Row.new(date: "2026-10-19").time_of_day
  end
end
