require "test_helper"

class SpanishHolidaysTest < ActiveSupport::TestCase
  test "knows Easter and the national and Madrid holidays" do
    assert_equal Date.new(2026, 4, 5), SpanishHolidays.easter_sunday(2026)
    assert_equal Date.new(2027, 3, 28), SpanishHolidays.easter_sunday(2027)

    assert SpanishHolidays.holiday?(Date.new(2026, 4, 2)), "Jueves Santo"
    assert SpanishHolidays.holiday?(Date.new(2026, 4, 3)), "Viernes Santo"
    assert SpanishHolidays.holiday?(Date.new(2026, 5, 15)), "San Isidro"
    assert SpanishHolidays.holiday?(Date.new(2026, 10, 12))
    assert_not SpanishHolidays.holiday?(Date.new(2026, 10, 13))
  end

  test "moves a date back or forward to a working day" do
    # Sunday 5 April 2026: Saturday, Viernes and Jueves Santo before it.
    assert_equal Date.new(2026, 4, 1), SpanishHolidays.previous_business_day(Date.new(2026, 4, 5))
    # Saturday 31 October 2026 -> Monday 2 November.
    assert_equal Date.new(2026, 11, 2), SpanishHolidays.next_business_day(Date.new(2026, 10, 31))
    # Thursday 29 October plus two working days -> Monday 2 November.
    assert_equal Date.new(2026, 11, 2), SpanishHolidays.add_business_days(Date.new(2026, 10, 29), 2)
  end
end
