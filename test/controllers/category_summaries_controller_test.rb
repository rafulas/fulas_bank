require "test_helper"

class CategorySummariesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @family.apply_default_categories!
  end

  test "index lists the root categories with movements and hides the empty ones" do
    hogar = @family.categories.find_by!(name: "Hogar")
    create_transaction(account: accounts(:depository), amount: 40, category: hogar)
    create_transaction(account: accounts(:depository), amount: 15, category: @family.categories.find_by!(name: "Excluido"))

    get category_summaries_url

    assert_response :success
    assert_select "a[href=?]", category_summary_path(hogar, period: @controller.instance_variable_get(:@period).key)
    assert_select "p", text: "Excluido"
    empty = @family.categories.roots.where.not(name: [ "Hogar", "Excluido", "Traspasos" ]).first
    assert_select "a[href=?]", category_summary_path(empty, period: @controller.instance_variable_get(:@period).key), count: 0
  end

  test "opens on the current month" do
    @user.update!(default_period: "last_30_days")

    get category_summaries_url

    assert_equal "current_month", @controller.instance_variable_get(:@period).key
  end

  test "index shows the rings, tags, calendar, merchants and last months" do
    get category_summaries_url

    assert_response :success
    assert_select "[data-controller='donut-chart']", count: 2
    assert_select "a[href=?]", new_tag_path
    assert_select "h2", text: I18n.t("category_summaries.analysis.analysis")
  end

  test "show breaks a category down by subcategory" do
    hogar = @family.categories.find_by!(name: "Hogar")

    get category_summary_url(hogar)

    assert_response :success
    assert_select "p", text: "Comunidad"
    assert_select "p", text: "Jardín y plantas"
  end

  test "show only accepts root categories of the family" do
    get category_summary_url(@family.categories.find_by!(name: "Comunidad"))

    assert_response :not_found
  end
end
