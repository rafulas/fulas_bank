require "test_helper"

class InsuranceLinkerTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @checking = accounts(:depository)
    @today = Date.current
    @insurance = @family.insurances.create!(
      name: "Seguro Cupra", kind: "car", payment_frequency: "custom", payment_account: @checking,
      installments: [
        { "date" => (@today - 40).iso8601, "amount" => "150" },
        { "date" => (@today + 5).iso8601, "amount" => "150" }
      ]
    )
  end

  def charge(amount:, date:, account: @checking)
    account.entries.create!(name: "MAPFRE SEGUROS", date: date, amount: amount, currency: account.currency, entryable: Transaction.new)
  end

  test "proposes the charge of each instalment, in the policy's account, a few days either side" do
    paid = charge(amount: 150.4, date: @today - 38)
    charge(amount: 150, date: @today - 38, account: accounts(:credit_card))

    assert_equal 1, InsuranceLinker.new(@family, today: @today).run!

    payment = @insurance.insurance_payments.find_by!(due_on: @today - 40)
    assert_equal paid, payment.entry
    assert payment.suggested?
    assert_equal :suggested, @insurance.reload.recent_instalments(@today).first.status(@today)
  end

  test "a rejected charge is not proposed again, and the instalment ends up overdue" do
    rejected = charge(amount: 150, date: @today - 40)
    InsuranceLinker.new(@family, today: @today).run!
    @insurance.insurance_payments.find_by!(due_on: @today - 40).reject_entry!

    assert_equal 0, InsuranceLinker.new(@family, today: @today).run!
    assert_includes @insurance.insurance_payments.find_by!(due_on: @today - 40).rejected_entry_ids, rejected.id
    assert_equal [ @today - 40 ], @insurance.reload.overdue_instalments(@today).map(&:date)
  end

  test "a charge far from the amount is not proposed" do
    charge(amount: 300, date: @today - 40)

    assert_equal 0, InsuranceLinker.new(@family, today: @today).run!
  end

  test "an instalment paid early is not expected again in the Forecast" do
    early = charge(amount: 150, date: @today - 1)
    @insurance.insurance_payments.create!(due_on: @today + 5, entry: early)

    forecast = Forecast.new(@family, accounts: [ @checking ], through: @today + 30, include_variable: false, today: @today)
    assert_empty forecast.flows.select { |flow| flow.source == :insurance && flow.date == @today + 5 }
  end
end
