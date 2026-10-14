require "test_helper"

class Import::BalanceCheckTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @account = accounts(:depository)
  end

  test "reads the bank's balance after the newest movement of the statement" do
    csv = "Fecha;Concepto;Importe;Disponible\n" \
          "02/10/2026;CAFE;-3,00;1.497,00\n" \
          "02/10/2026;MERCADONA;-50,00;1.500,00\n" \
          "01/10/2026;NOMINA;1.550,00;1.550,00\n"
    import = @family.imports.create!(type: "TransactionImport", account: @account, raw_file_str: csv, col_sep: ";")
    Import::BankPreset.apply(import)

    result = Import::BankBalance.detect(import.reload)

    assert_equal Date.new(2026, 10, 2), result.date
    assert_equal BigDecimal("1497"), result.amount
  end

  test "has no bank balance for a file of several accounts or without the column" do
    csv = "Fecha;Concepto;Importe\n01/10/2026;NOMINA;1.550,00\n"
    import = @family.imports.create!(type: "TransactionImport", account: @account, raw_file_str: csv, col_sep: ";")
    Import::BankPreset.apply(import)
    assert_nil Import::BankBalance.detect(import.reload)

    import.update!(account: nil)
    assert_nil Import::BankBalance.detect(import)
  end

  test "compares the statement's balance with the app's on that day" do
    import = completed_import(csv: "Fecha;Concepto;Importe;Disponible\n#{Date.current.strftime('%d/%m/%Y')};MERCADONA;-50,00;950,00\n")
    @account.balances.create!(date: Date.current, balance: 1000, currency: "USD", start_cash_balance: 1000)

    check = Import::BalanceCheck.new(import, user: @user).checks.sole

    assert_equal "statement", check.source
    assert_equal BigDecimal("950"), check.bank_amount
    assert_equal BigDecimal("1000"), check.app_amount
    assert check.mismatched?
    assert_equal BigDecimal("-50"), check.difference
  end

  test "keeps a typed balance and says whether it matches" do
    import = completed_import
    @account.balances.create!(date: Date.current, balance: 1000, currency: "USD", start_cash_balance: 1000)
    balance_check = Import::BalanceCheck.new(import, user: @user)

    assert_not balance_check.checks.sole.checked?

    balance_check.record!(@account, BigDecimal("1000"))
    check = Import::BalanceCheck.new(import.reload, user: @user).checks.sole

    assert_equal "typed", check.source
    assert check.matched?
  end

  test "waits while balances are being recalculated" do
    import = completed_import
    balance_check = Import::BalanceCheck.new(import, user: @user)
    balance_check.record!(@account, BigDecimal("10"))
    @family.syncs.create!(status: "syncing")

    assert balance_check.checks.sole.pending?
    assert balance_check.any_pending?
  end

  test "adjusts the account to the bank's balance" do
    import = completed_import
    @account.balances.create!(date: Date.current, balance: 1000, currency: "USD", start_cash_balance: 1000)
    balance_check = Import::BalanceCheck.new(import, user: @user)
    balance_check.record!(@account, BigDecimal("1234.56"))

    assert_difference -> { @account.entries.where(entryable_type: "Valuation").count } => 1 do
      assert balance_check.adjust!(@account)
    end
    assert_equal BigDecimal("1234.56"), @account.entries.where(entryable_type: "Valuation", date: Date.current).sole.amount
  end

  private
    def completed_import(csv: "Fecha;Concepto;Importe\n#{Date.current.strftime('%d/%m/%Y')};MERCADONA;-50,00\n")
      import = @family.imports.create!(type: "TransactionImport", account: @account, raw_file_str: csv, col_sep: ";", status: :complete)
      Import::BankPreset.apply(import)
      create_transaction(account: @account, name: "MERCADONA", amount: 50, import: import)
      import.reload
    end
end
