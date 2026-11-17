require "test_helper"

class Settings::SecuritiesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:family_admin) }

  test "shows encryption warning when self-hosted and encryption is not configured" do
    Rails.configuration.stubs(:app_mode).returns("self_hosted".inquiry)
    ActiveRecordEncryptionConfig.stubs(:explicitly_configured?).returns(false)

    get settings_security_url

    assert_response :success
    assert_includes response.body, I18n.t("settings.securities.show.encryption_warning.title")
  end

  test "hides encryption warning when encryption is configured" do
    Rails.configuration.stubs(:app_mode).returns("self_hosted".inquiry)
    ActiveRecordEncryptionConfig.stubs(:explicitly_configured?).returns(true)

    get settings_security_url

    assert_response :success
    assert_not_includes response.body, I18n.t("settings.securities.show.encryption_warning.title")
  end

  test "does not show encryption warning in managed mode" do
    Rails.configuration.stubs(:app_mode).returns("managed".inquiry)

    get settings_security_url

    assert_response :success
    assert_not_includes response.body, I18n.t("settings.securities.show.encryption_warning.title")
  end

  test "shows the open sessions and the latest security changes" do
    user = users(:family_admin)
    request = ActionDispatch::TestRequest.create
    SecurityAuditLog.log_password_changed!(user: user, request: request)

    get settings_security_path

    assert_response :success
    assert_select "h4", text: I18n.t("settings.securities.show.sessions_title")
    assert_match I18n.t("settings.securities.show.events.password_changed"), response.body
    assert_match I18n.t("settings.securities.show.this_device"), response.body
  end
end
