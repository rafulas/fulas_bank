require "test_helper"

class Rules::SuggestionsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    3.times do |index|
      create_transaction(account: accounts(:depository), name: "REPSOL WAYLET #{index}", amount: 60,
                         category: categories(:food_and_drink), date: Date.current - index)
    end
  end

  test "lists the suggestions and links to them from the rules" do
    get rules_url
    assert_select "a[href='#{rule_suggestions_path}']"

    get rule_suggestions_url

    assert_response :success
    assert_match "REPSOL", response.body
  end

  test "creates a suggested rule" do
    assert_difference -> { @user.family.rules.count } => 1 do
      post rule_suggestions_url(id: "expense:REPSOL")
    end

    assert_redirected_to rule_suggestions_url
    assert_equal "REPSOL", @user.family.rules.order(:created_at).last.name
  end

  test "dismisses a suggestion for good" do
    post dismiss_rule_suggestions_url(id: "expense:REPSOL")

    assert_redirected_to rule_suggestions_url
    assert_includes @user.reload.preferences[Rules::SuggestionsController::DISMISSED_PREFERENCE], "expense:REPSOL"

    get rule_suggestions_url
    assert_no_match "REPSOL WAYLET", response.body
  end
end
