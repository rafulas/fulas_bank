require "test_helper"

class DS::FilledIconTest < ViewComponent::TestCase
  test "text fallback renders one letter by default" do
    render_inline(DS::FilledIcon.new(text: "Example"))

    assert_text "E"
    assert_no_text "Ex"
  end

  test "text fallback can render multiple initials when requested" do
    render_inline(DS::FilledIcon.new(text: "EX", text_length: 2))

    assert_text "EX"
  end

  test "accepts extra container classes" do
    render_inline(DS::FilledIcon.new(text: "EX", text_length: 2, class_name: "w-full h-full"))

    assert_selector ".w-full.h-full", text: "EX"
  end

  test "solid variant fills the shape with the color" do
    render_inline(DS::FilledIcon.new(variant: :solid, icon: "home", hex_color: "#b0bc3c", rounded: true))

    assert_selector "div.rounded-full[style*='background-color: #b0bc3c']"
  end
end
