require "test_helper"

class StatusReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "shows every section for every account the first time" do
    get status_report_url

    assert_response :success
    StatusReport::SECTIONS.each do |section|
      next if section == "summary"

      assert_select "#report-#{section}"
    end
    assert_select "#report-summary"
    assert_select "textarea[data-report-copy-target=source]"
  end

  test "shows only the ticked accounts and sections" do
    get status_report_url, params: { account_ids: [ "", accounts(:depository).id ], sections: [ "", "balances" ], period: "current_year" }

    assert_response :success
    assert_select "#report-balances"
    assert_select "#report-loans", count: 0
    assert_select "#report-balances textarea", text: /#{Regexp.escape(accounts(:depository).name)}/
  end

  test "saves the current choices with a name and opens them again" do
    assert_difference -> { @user.report_presets.count } => 1 do
      post report_presets_url, params: { report_preset: { name: "Para casa", account_ids: [ accounts(:depository).id ],
                                                         sections: %w[summary balances], period: "last_month" } }
    end
    preset = @user.report_presets.last
    assert_redirected_to status_report_url(preset_id: preset.id)
    assert_equal [ accounts(:depository).id ], preset.account_ids
    assert_equal %w[summary balances], preset.sections

    get status_report_url(preset_id: preset.id)
    assert_response :success
    assert_select "#report-balances"
    assert_select "#report-forecast", count: 0

    assert_difference -> { @user.report_presets.count } => -1 do
      delete report_preset_url(preset)
    end
  end
end
