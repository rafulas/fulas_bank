require "test_helper"

class PropertyTest < ActiveSupport::TestCase
  test "measures area in square metres by default" do
    assert_equal "sqm", Property.new.area_unit
  end

  test "every property type has a Spanish name" do
    I18n.with_locale(:es) do
      Property::SUBTYPES.each do |subtype, labels|
        assert_not_equal labels[:long], Property.long_subtype_label_for(subtype), "#{subtype} is not translated"
      end
    end
  end
end
