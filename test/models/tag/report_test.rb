require "test_helper"

class Tag::ReportTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @family = @user.family
    @tag = @family.tags.create!(name: "Viaje La Manga")
    @period = Period.custom(start_date: Date.current.beginning_of_month, end_date: Date.current.end_of_month)
  end

  test "adds up only the transactions with the tag, expenses negative" do
    create_transaction(date: Date.current.beginning_of_month, amount: 120, category: categories(:food_and_drink), tags: [ @tag ])
    create_transaction(date: Date.current.beginning_of_month, amount: 30, tags: [ @tag ])
    create_transaction(date: Date.current.beginning_of_month, amount: 999, category: categories(:food_and_drink))

    report = report_for(@period)

    assert_equal(-150, report.total)
    assert_equal 2, report.transactions_count
    assert_includes report.category_rows.map { |row| row.category.name }, categories(:food_and_drink).name
    assert_equal(-120, report.category_rows.find { |row| row.category.id == categories(:food_and_drink).id }.total)
  end

  test "goes month by month for the last six months and averages them" do
    create_transaction(date: Date.current.beginning_of_month, amount: 60, tags: [ @tag ])
    create_transaction(date: (Date.current << 2).beginning_of_month, amount: 240, tags: [ @tag ])
    create_transaction(date: (Date.current << 7).beginning_of_month, amount: 1000, tags: [ @tag ])

    report = report_for(@period)

    assert_equal Tag::Report::MONTHS, report.months.size
    assert_equal Date.current.beginning_of_month, report.months.last.date
    assert_equal(-60, report.months.last.total)
    assert_equal(-240, report.months[-3].total)
    assert_equal(-300, report.months_total)
    assert_equal(-50, report.average)
  end

  test "opens the same tag and period in the Transactions page" do
    filters = report_for(@period).search_filters

    assert_equal [ "Viaje La Manga" ], filters[:tags]
    assert_equal @period.start_date.iso8601, filters[:start_date]
  end

  private
    def report_for(period)
      Tag::Report.new(@tag, period: period, user: @user)
    end
end
