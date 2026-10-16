require "test_helper"

class SidebarNavItemViewTest < ActionView::TestCase
  test "shows the name beside the icon and marks the active page" do
    html = render(partial: "layouts/shared/sidebar_nav_item", locals: {
      name: "Transacciones",
      path: "/transactions",
      icon: "credit-card",
      icon_custom: false,
      active: true
    })

    assert_includes html, "aria-current=\"page\""
    assert_includes html, "Transacciones"
    assert_includes html, "bg-nav-indicator"
  end

  test "inactive item omits aria-current" do
    html = render(partial: "layouts/shared/sidebar_nav_item", locals: {
      name: "Transacciones",
      path: "/transactions",
      icon: "credit-card",
      icon_custom: false,
      active: false
    })

    assert_not_includes html, "aria-current"
    assert_not_includes html, "bg-nav-indicator"
  end
end
