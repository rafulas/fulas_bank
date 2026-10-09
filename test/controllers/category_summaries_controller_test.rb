require "test_helper"

class CategorySummariesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @family.apply_default_categories!
  end

  test "index lists the root categories" do
    get category_summaries_url

    assert_response :success
    assert_select "a[href=?]", category_summary_path(@family.categories.find_by!(name: "Hogar"), period: @controller.instance_variable_get(:@period).key)
    assert_select "p", text: "Excluido"
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
