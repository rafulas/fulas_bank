require "test_helper"

class SpendingSplitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @food = categories(:food_and_drink)
    @restaurants = categories(:subcategory)
  end

  test "the Resumen shows the split and the settings save the target and the classes" do
    get category_summaries_url
    assert_response :success
    assert_select "a[href=?]", edit_spending_split_path

    get edit_spending_split_url
    assert_response :success
    assert_select "select[name=?]", "classes[#{@restaurants.id}]"

    patch spending_split_url, params: { target: %w[60 25 15], classes: { @food.id => "essential", @restaurants.id => "discretionary" } }

    assert_redirected_to category_summaries_url
    assert_equal [ 60, 25, 15 ], @user.reload.preferences[Category::SpendingSplit::TARGET_PREFERENCE]
    assert_equal "essential", @food.reload.spending_class
    assert_equal "discretionary", @restaurants.reload.effective_spending_class
  end

  test "a target that does not add up to 100 is refused" do
    patch spending_split_url, params: { target: %w[60 30 20] }

    assert_equal I18n.t("spending_splits.update.invalid_target"), flash[:alert]
  end
end
