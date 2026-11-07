require "test_helper"

class OverdraftWarningTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @user = users(:empty)
    @today = Date.current
    @checking = @family.accounts.create!(name: "BBVA", owner: @user, balance: 100, currency: "USD",
                                         accountable: Depository.new(subtype: "checking"))
  end

  test "warns of the first day a current account goes below zero, with the charge behind it" do
    planned("Alquiler", 30, @today + 3.days)
    planned("Luz", 95, @today + 5.days)

    warning = OverdraftWarning.new(@family, user: @user, today: @today).warnings.sole

    assert warning.overdraft?
    assert_equal @checking, warning.account
    assert_equal @today + 5.days, warning.date
    assert_equal Money.new(-25, "USD"), warning.balance
    assert_equal "Luz", warning.culprit_name
  end

  test "says nothing when the money lasts" do
    planned("Luz", 95, @today + 5.days, nature: "outflow")
    planned("Nómina", 1_000, @today + 2.days, nature: "inflow")

    assert_not OverdraftWarning.new(@family, user: @user, today: @today).any?
  end

  test "looks only a few weeks ahead" do
    planned("Seguro", 500, @today + OverdraftWarning::HORIZON_DAYS.days + 10.days)

    assert_not OverdraftWarning.new(@family, user: @user, today: @today).any?
  end

  test "warns more softly below the cushion of the main account" do
    @user.update_dashboard_preferences(Forecast::CUSHION_PREFERENCE => "80")
    planned("Luz", 30, @today + 4.days)

    warning = OverdraftWarning.new(@family, user: @user.reload, today: @today).warnings.sole

    assert warning.below_cushion
    assert_equal Money.new(70, "USD"), warning.balance
  end

  private
    def planned(name, amount, date, nature: "outflow")
      @family.forecast_items.create!(account: @checking, name: name, nature: nature, amount: amount, date: date, currency: "USD")
    end
end
