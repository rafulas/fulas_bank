require "test_helper"

class MeasurementTest < ActiveSupport::TestCase
  test "writes square metres with their symbol" do
    assert_equal "120 m²", Measurement.new(120, "sqm").to_s
  end

  test "keeps distances as they are" do
    assert_equal "15000 km", Measurement.new(15_000, "km").to_s
  end
end
