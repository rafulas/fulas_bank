# frozen_string_literal: true

require "test_helper"

class Api::V1::QuickEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @account = accounts(:depository)

    @user.api_keys.active.destroy_all

    @api_key = ApiKey.create!(
      user: @user,
      name: "Test Read-Write Key",
      scopes: [ "read_write" ],
      source: "web",
      display_key: "test_rw_#{SecureRandom.hex(8)}"
    )

    @read_only_api_key = ApiKey.create!(
      user: @user,
      name: "Test Read-Only Key",
      scopes: [ "read" ],
      display_key: "test_ro_#{SecureRandom.hex(8)}",
      source: "mobile"
    )

    Redis.new.del("api_rate_limit:#{@api_key.id}")
    Redis.new.del("api_rate_limit:#{@read_only_api_key.id}")
  end

  test "records an expense from plain words" do
    assert_difference -> { @account.entries.count }, 1 do
      post api_v1_quick_entries_url,
           params: { text: "4,50 starbucks", account_id: @account.id },
           headers: api_headers(@api_key)
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "Starbucks", body["name"]
    assert_equal "expense", body["nature"]
    assert_equal @account.id, body.dig("account", "id")
    assert_equal categories(:food_and_drink).name, body.dig("category", "name")
    assert_equal Date.current.iso8601, body["date"]
    assert_includes body["message"], "Starbucks"
  end

  test "records income on the given date" do
    post api_v1_quick_entries_url,
         params: { text: "+1.250 nómina", account_id: @account.id, date: 2.days.ago.to_date.iso8601 },
         headers: api_headers(@api_key)

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "income", body["nature"]
    assert_equal 2.days.ago.to_date.iso8601, body["date"]
    assert_equal BigDecimal("-1250"), @account.entries.find(body["entry_id"]).amount
  end

  test "answers in the user's language" do
    @user.update!(locale: "es")

    post api_v1_quick_entries_url,
         params: { text: "café", account_id: @account.id },
         headers: api_headers(@api_key)

    assert_response :unprocessable_entity
    assert_equal I18n.t("quick_entries.errors.amount_missing", locale: :es), JSON.parse(response.body)["message"]
  end

  test "rejects text without an amount" do
    assert_no_difference -> { Entry.count } do
      post api_v1_quick_entries_url, params: { text: "café" }, headers: api_headers(@api_key)
    end

    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
  end

  test "rejects an invalid date" do
    post api_v1_quick_entries_url,
         params: { text: "12 café", date: "31-02-2026" },
         headers: api_headers(@api_key)

    assert_response :unprocessable_entity
  end

  test "rejects an account the user cannot write to" do
    post api_v1_quick_entries_url,
         params: { text: "12 café", account_id: SecureRandom.uuid },
         headers: api_headers(@api_key)

    assert_response :unprocessable_entity
  end

  test "a read-only key cannot record" do
    assert_no_difference -> { Entry.count } do
      post api_v1_quick_entries_url,
           params: { text: "12 café", account_id: @account.id },
           headers: api_headers(@read_only_api_key)
    end

    assert_response :forbidden
  end

  test "requires authentication" do
    post api_v1_quick_entries_url, params: { text: "12 café" }

    assert_response :unauthorized
  end

  private
    def api_headers(api_key)
      { "X-Api-Key" => api_key.plain_key }
    end
end
