require "test_helper"

class Import::AccountGuessTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
  end

  test "reads the bank code and the last digits of the IBAN, masked or not" do
    assert_equal "0182-1234", Import::StatementReference.from(file_fixture("imports/bbva.xlsx").binread)
    assert_equal "0182-4567", Import::StatementReference.from("Cuenta;ES76 0182 2370 4202 0123 4567\nFecha;Concepto;Importe\n")
    assert_nil Import::StatementReference.from("Fecha;Concepto;Importe\n01/10/2026;NOMINA;1.550,00\n")
  end

  test "recognises the account that imported a statement with the same IBAN" do
    @account.update!(statement_reference: "0182-1234")
    import = statement_import(reference: "0182-1234")

    result = Import::AccountGuess.new(import, accounts: @family.accounts.to_a).guess

    assert_equal @account, result.account
    assert_equal :reference, result.reason
  end

  test "recognises the account whose balance the day before matches the statement's" do
    @account.balances.create!(date: Date.new(2020, 3, 31), balance: BigDecimal("1234.56"), currency: @account.currency, start_cash_balance: BigDecimal("1234.56"))
    import = statement_import(csv: "Fecha;Concepto;Importe;Disponible\n" \
                                   "02/04/2020;CAFE;-3,00;1.131,56\n" \
                                   "01/04/2020;MERCADONA;-100,00;1.134,56\n")

    result = Import::AccountGuess.new(import, accounts: @family.accounts.to_a).guess

    assert_equal @account, result.account
    assert_equal :balance, result.reason
  end

  test "takes the only current account, and guesses nothing among several" do
    family = families(:empty)
    only = family.accounts.create!(name: "BBVA", balance: 0, currency: "EUR", accountable: Depository.new)
    import = family.imports.create!(type: "TransactionImport", raw_file_str: "Fecha;Concepto;Importe\n01/10/2026;NOMINA;1.550,00\n", col_sep: ";")
    Import::BankPreset.apply(import)

    assert_equal only, Import::AccountGuess.new(import.reload, accounts: family.accounts.to_a).guess.account

    family.accounts.create!(name: "Otra", balance: 0, currency: "EUR", accountable: Depository.new)
    assert_nil Import::AccountGuess.new(import, accounts: family.accounts.reload.to_a).guess
  end

  test "an account learns the IBAN of the statement imported into it" do
    import = statement_import(reference: "0182-1234")
    import.update!(account: @account)

    import.remember_statement_reference!

    assert_equal "0182-1234", @account.reload.statement_reference
  end

  private
    def statement_import(csv: "Fecha;Concepto;Importe\n01/10/2026;NOMINA;1.550,00\n", reference: nil)
      import = @family.imports.create!(type: "TransactionImport", raw_file_str: csv, col_sep: ";", statement_reference: reference)
      Import::BankPreset.apply(import)
      import.reload
    end
end
