require "test_helper"

class StyledFormBuilderTest < ActionView::TestCase
  include PeriodPickerHelper

  # The date field's calendar button draws an icon; the icon itself is not
  # what these tests look at.
  def icon(*)
    tag.svg
  end

  setup do
    @builder = StyledFormBuilder.new(:account_statement, nil, self, {})
  end

  test "a labelled file field sits in a form field with its label" do
    field = Nokogiri::HTML.fragment(@builder.file_field(:files, label: "Statement files")).at(".form-field")

    assert field, "expected the file input wrapped in a .form-field"
    assert_equal "account_statement_files", field.at("label.form-field__label")["for"]
    assert_includes field.at("input[type=file]")["class"].split, "file:bg-container-inset"
  end

  # The dropzones pass `hidden` and draw their own target: no wrapper, and
  # their classes merged in rather than replaced.
  test "an unlabelled file field comes back bare and keeps the caller's classes" do
    fragment = Nokogiri::HTML.fragment(@builder.file_field(:files, class: "hidden"))

    assert_nil fragment.at(".form-field")
    assert_includes fragment.at("input[type=file]")["class"].split, "hidden"
  end

  # Fulas Bank: every date field gets the app's calendar, and stays a real
  # date input that can be typed into.
  test "a date field gets the calendar button and keeps the date input" do
    field = Nokogiri::HTML.fragment(@builder.date_field(:statement_date, label: "Fecha")).at(".form-field")

    wrapper = field.at("[data-controller='date-field']")
    assert wrapper
    input = wrapper.at("input[type=date]")
    assert_equal "input", input["data-date-field-target"]
    assert_includes input["class"].split, "form-field__input"
    assert wrapper.at("button[data-date-field-target='button']")
  end
end
