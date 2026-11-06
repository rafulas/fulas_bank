require "test_helper"

class PerformanceLogTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "writes where a page's time went when FULAS_PERF_LOG is set" do
    messages = []
    Rails.logger.stubs(:warn).with { |message| messages << message.to_s }

    with_env_overrides(FULAS_PERF_LOG: "1") { get transactions_url }

    assert_response :success
    line = messages.find { |message| message.start_with?("[perf] GET /transactions") }
    assert line, "expected a [perf] line, got #{messages.inspect}"
    assert_match(/SQL \d+ consultas \d+ms/, line)
    assert_match(/más lento: \S/, line)
  end

  test "lists the Forecast's own steps" do
    messages = []
    Rails.logger.stubs(:warn).with { |message| messages << message.to_s }

    with_env_overrides(FULAS_PERF_LOG: "1") { get forecast_url }

    assert_response :success
    line = messages.find { |message| message.start_with?("[perf] GET /forecast") }
    assert line, "expected a [perf] line, got #{messages.inspect}"
    assert_match(/pasos: .*forecast\.recurrentes \d+ms/, line)
    assert_match(/forecast\.grafica \d+ms/, line)
  end

  test "writes nothing without FULAS_PERF_LOG" do
    messages = []
    Rails.logger.stubs(:warn).with { |message| messages << message.to_s }

    with_env_overrides(FULAS_PERF_LOG: nil) { get transactions_url }

    assert_response :success
    assert_empty messages.grep(/\A\[perf\]/)
  end
end
