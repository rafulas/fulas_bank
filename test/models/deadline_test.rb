require "test_helper"

class DeadlineTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @today = Date.new(2026, 11, 7)
  end

  test "is due soon within its reminder window and overdue after its date" do
    deadline = build(due_on: @today + 20.days, remind_days: 30)

    assert deadline.due_soon?(@today)
    assert_not deadline.overdue?(@today)
    assert_not build(due_on: @today + 40.days, remind_days: 30).due_soon?(@today)
    assert build(due_on: @today - 1.day).overdue?(@today)
  end

  test "a repeating one moves to its next date when done" do
    deadline = create(due_on: Date.new(2026, 11, 1), repeat_months: 12)

    deadline.complete!(@today)

    assert_equal Date.new(2027, 11, 1), deadline.due_on
    assert_not deadline.completed?
  end

  test "a repeating one done ahead of its date moves one period on" do
    deadline = create(due_on: @today + 10.days, repeat_months: 24)

    deadline.complete!(@today)

    assert_equal (@today + 10.days).advance(years: 2), deadline.due_on
  end

  test "a one-off is kept as done and can be reopened" do
    deadline = create(due_on: @today)

    deadline.complete!(@today)
    assert_equal @today, deadline.completed_on

    deadline.reopen!
    assert_not deadline.completed?
  end

  test "takes the currency of its account and rejects another family's account" do
    account = accounts(:depository)
    assert_equal account.currency, create(account: account).currency

    other = families(:empty).accounts.create!(name: "Ajena", balance: 0, currency: "USD", accountable: Depository.new)
    assert_not build(account: other).valid?
  end

  test "a vehicle suggests the ITV" do
    assert_equal "itv", Deadline.default_kind_for(accounts(:vehicle))
    assert_equal "other", Deadline.default_kind_for(nil)
  end

  test "upcoming lists deadlines in their window and policies about to renew" do
    create(name: "ITV", due_on: @today + 10.days)
    create(name: "DNI", due_on: @today + 200.days)
    create(name: "Garantía", due_on: @today + 5.days, completed_on: @today)
    @family.insurances.create!(name: "Hogar", kind: "home", renewal_date: @today + 3.days, currency: "USD")

    names = Deadline::Upcoming.new(@family, today: @today).items.map(&:name)

    assert_equal [ "Hogar", "ITV" ], names
  end

  private
    def build(**attributes)
      @family.deadlines.new({ name: "ITV", kind: "itv", due_on: @today }.merge(attributes))
    end

    def create(**attributes)
      build(**attributes).tap(&:save!)
    end
end
