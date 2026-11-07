require "test_helper"

class RecapTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @user = users(:empty)
    @account = @family.accounts.create!(name: "Recap checking", owner: @user, balance: 0, currency: "USD", accountable: Depository.new)
    @food = @family.categories.create!(name: "Comida", color: "#22c55e")
    @home = @family.categories.create!(name: "Hogar", color: "#84cc16")
    @today = Date.new(2026, 11, 7) # a Saturday
  end

  test "a week runs Monday to Sunday and is named by ISO week" do
    recap = recap_for("week", Date.new(2026, 11, 4))

    assert_equal Date.new(2026, 11, 2), recap.start_date
    assert_equal Date.new(2026, 11, 8), recap.end_date
    assert_equal "2026-W45", recap.to_param
    assert_not recap.closed?
    assert_nil recap.next
  end

  test "a month follows the calendar unless the family starts it another day" do
    assert_equal [ Date.new(2026, 10, 1), Date.new(2026, 10, 31) ], bounds(recap_for("month", Date.new(2026, 10, 14)))

    @family.update!(month_start_day: 25)
    recap = Recap.from_param(@family, "2026-10", user: @user, today: @today)

    assert_equal [ Date.new(2026, 10, 25), Date.new(2026, 11, 24) ], bounds(recap)
    assert_equal "2026-10", recap.to_param
  end

  test "reads its own params back and rejects anything else" do
    assert_equal "2026-W44", Recap.from_param(@family, "2026-W44", user: @user, today: @today).to_param
    assert_equal "2026-09", Recap.from_param(@family, "2026-09", user: @user, today: @today).to_param
    assert_nil Recap.from_param(@family, "2026-13", user: @user, today: @today)
    assert_nil Recap.from_param(@family, "2026-W60", user: @user, today: @today)
    assert_nil Recap.from_param(@family, "nope", user: @user, today: @today)
  end

  test "previous and next walk the periods" do
    recap = recap_for("month", Date.new(2026, 10, 14))

    assert_equal "2026-09", recap.previous.to_param
    assert_equal "2026-11", recap.next.to_param
  end

  test "the latest closed recaps are offered for a few days" do
    assert_equal [ "2026-10", "2026-W44" ], Recap.fresh(@family, user: @user, today: Date.new(2026, 11, 3)).map(&:to_param)
    assert_equal [ "2026-10" ], Recap.fresh(@family, user: @user, today: Date.new(2026, 11, 5)).map(&:to_param)
    assert_empty Recap.fresh(@family, user: @user, today: Date.new(2026, 11, 13))
  end

  test "compares with the period before and finds what moved" do
    create_transaction(account: @account, amount: 100, date: Date.new(2026, 9, 10), category: @food, currency: "USD")
    create_transaction(account: @account, amount: 50, date: Date.new(2026, 9, 12), category: @home, currency: "USD")
    create_transaction(account: @account, amount: 40, date: Date.new(2026, 10, 10), category: @food, currency: "USD")
    create_transaction(account: @account, amount: 300, date: Date.new(2026, 10, 12), category: @home, currency: "USD", name: "Sofá")
    create_transaction(account: @account, amount: -1_000, date: Date.new(2026, 10, 1), currency: "USD", name: "Nómina")

    recap = recap_for("month", Date.new(2026, 10, 14))

    assert_equal BigDecimal("340"), recap.spent.amount
    assert_in_delta 126.67, recap.spent_change.to_f, 0.01
    assert_nil recap.income_change
    assert_equal [ [ "Hogar", 250 ], [ "Comida", -60 ] ], recap.category_changes.map { |change| [ change.name, change.delta.to_i ] }
    assert_equal "Sofá", recap.biggest_expenses.first.name
    assert_equal 66, recap.savings_rate
  end

  test "the LLM writes the report from the facts when AI is on" do
    create_transaction(account: @account, amount: 40, date: Date.new(2026, 10, 10), category: @food, currency: "USD")
    provider = mock("provider")
    message = stub(output_text: "Un buen mes\nGastaste poco.")
    provider.expects(:chat_response).with { |*args| args.first.to_s.include?("\"spent\"") }
            .returns(stub(success?: true, data: stub(messages: [ message ])))
    Recap::Report.any_instance.stubs(:provider).returns(provider)
    Recap::Report.any_instance.stubs(:llm_model).returns("test-model")

    report = Recap::Report.new(recap_for("month", Date.new(2026, 10, 14))).result

    assert report.ai
    assert_equal "Un buen mes", report.headline
    assert_equal "Gastaste poco.", report.body
  end

  test "the template report repeats the period's figures" do
    create_transaction(account: @account, amount: 100, date: Date.new(2026, 9, 10), category: @food, currency: "USD")
    create_transaction(account: @account, amount: 40, date: Date.new(2026, 10, 10), category: @food, currency: "USD")

    Recap::Report.any_instance.stubs(:provider).returns(nil)
    report = I18n.with_locale(:es) { Recap::Report.new(recap_for("month", Date.new(2026, 10, 14))).result }

    assert_not report.ai
    assert_equal I18n.t("recaps.report.headline.negative", locale: :es), report.headline
    assert_includes report.body, "octubre"
    assert_includes report.body, "60 %"
  end

  test "an empty period says so" do
    Recap::Report.any_instance.stubs(:provider).returns(nil)
    report = Recap::Report.new(recap_for("week", Date.new(2026, 10, 20))).result

    assert_equal I18n.t("recaps.report.headline.quiet"), report.headline
  end

  private
    def recap_for(kind, date)
      Recap.for(@family, user: @user, kind: kind, date: date, today: @today)
    end

    def bounds(recap)
      [ recap.start_date, recap.end_date ]
    end
end
