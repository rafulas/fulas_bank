require "test_helper"

class DS::ColorLabelTest < ViewComponent::TestCase
  test "a category shows its icon on a square of its color, then its name" do
    render_inline(DS::ColorLabel.new(label: "Combustible", color: "#506cd8", icon: "fuel", detail: "Transporte", label_testid: "category-name"))

    assert_selector "span[aria-hidden='true'][style*='#506cd8'] svg"
    assert_selector "[data-testid='category-name']", text: "Combustible · Transporte"
  end

  test "a tag shows a dot of its color" do
    render_inline(DS::ColorLabel.new(label: "Viaje Roma", color: "#6471eb", mark: :dot))

    assert_selector "span.rounded-full[style*='#6471eb']"
    assert_no_selector "svg"
    assert_text "Viaje Roma"
  end

  test "dashed marks nothing chosen yet, without the color" do
    render_inline(DS::ColorLabel.new(label: "Uncategorized", color: "#737373", icon: "circle-dashed", dashed: true))

    assert_selector "span.border-dashed"
    assert_no_selector "[style*='background-color']"
  end

  test "without the label it keeps the name for screen readers" do
    render_inline(DS::ColorLabel.new(label: "Supermercado", color: "#68b448", icon: "shopping-cart", show_label: false))

    assert_selector "span.sr-only", text: "Supermercado", visible: :all
  end

  test "an invalid color falls back to gray" do
    render_inline(DS::ColorLabel.new(label: "X", color: "red;background:url(x)", mark: :dot))

    assert_selector "span[style*='#{DS::ColorLabel::DEFAULT_COLOR}']"
  end
end
