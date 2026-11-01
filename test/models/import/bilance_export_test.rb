require "test_helper"

class Import::BilanceExportTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @csv = file_fixture("imports/bilance.csv").read
  end

  test "recognises a Bilance export and configures its columns" do
    import = @family.imports.create!(type: "TransactionImport", raw_file_str: @csv, col_sep: ",", account: accounts(:credit_card))

    result = Import::BankPreset.apply(import)
    import.reload

    assert_equal [ "bilance", "Bilance" ], [ result.key, result.bank_name ]
    assert_equal [ "Fecha", "Título", "Importe", "Categoría", "Etiquetas", "Concepto" ],
                 [ import.date_col_label, import.name_col_label, import.amount_col_label,
                   import.category_col_label, import.tags_col_label, import.notes_col_label ]
    assert_nil import.account_col_label
    assert_equal "Comercio", import.merchant_col_label
    assert_equal [ "1,234.56", "%Y-%m-%d", "inflows_positive", "signed_amount" ],
                 [ import.number_format, import.date_format, import.signage_convention, import.amount_type_strategy ]
  end

  test "into one account, a transfer to it is money in and one from it money out" do
    import = configured_import(account: accounts(:credit_card))

    rows = import.rows.ordered.index_by(&:name)

    assert_equal 4, rows.size
    assert_equal BigDecimal("75.29"), rows["Repsol Waylet"].signed_amount
    assert_equal BigDecimal("-12.50"), rows["Devolución"].signed_amount
    assert_equal BigDecimal("-449.97"), rows["Adeudo mensual de tarjeta"].signed_amount
    assert_equal BigDecimal("20.00"), rows["Paso a la cuenta"].signed_amount
  end

  test "with the accounts column, each transfer becomes both its sides" do
    import = configured_import

    transfers = import.rows.select { |row| row.name == "Adeudo mensual de tarjeta" }.sort_by(&:account)

    assert_equal [ [ "Cuenta Mano a mano", BigDecimal("449.97") ], [ "Tarjeta Repsol", BigDecimal("-449.97") ] ],
                 transfers.map { |row| [ row.account, row.signed_amount ] }
    assert_equal 6, import.rows.count
  end

  test "reads Comercio as the merchant and keeps both Nota and Concepto in the notes" do
    csv = <<~CSV
      Título,Fecha,Importe,Categoría,Subcategoría,Etiquetas,Concepto,Comercio,Cuentas,Nota
      Revisión moto,2026-10-07 00:00:00.000,-120.00€,Transporte,,,PAGO CON TARJETA // TALLER,Taller Pepe,Tarjeta Repsol,"Cambio de aceite
      y filtro"
      Lidl,2026-10-06 00:00:00.000,-45.98€,Compras,,,COMPRA LIDL,,Tarjeta Repsol,
      Café,2026-10-05 00:00:00.000,-2.10€,Compras,,,,,Tarjeta Repsol,Con Mar
    CSV
    import = @family.imports.create!(type: "TransactionImport", raw_file_str: csv, col_sep: ",", account: accounts(:credit_card))
    Import::BankPreset.apply(import)
    import.reload.generate_rows_from_csv

    assert_equal "Comercio", import.reload.merchant_col_label
    rows = import.rows.index_by(&:name)
    assert_equal "Taller Pepe", rows["Revisión moto"].merchant
    assert_equal "Cambio de aceite\ny filtro\n\nPAGO CON TARJETA // TALLER", rows["Revisión moto"].notes
    assert_equal "COMPRA LIDL", rows["Lidl"].notes
    assert_equal "Con Mar", rows["Café"].notes
    assert_equal "", rows["Lidl"].merchant.to_s
  end

  test "joins category and subcategory" do
    import = configured_import(account: accounts(:credit_card))

    categories = import.rows.ordered.map(&:category)

    assert_includes categories, "Transporte:Combustible"
    assert_includes categories, "Compras"
  end

  test "reads amounts with a euro sign in a generic statement" do
    csv = "Concepto;Fecha;Importe\nMERCADONA;29/09/2026;-54.37€\nNOMINA;28/09/2026;1850.00€\n"
    import = @family.imports.create!(type: "TransactionImport", raw_file_str: csv, col_sep: ";")

    Import::BankPreset.apply(import)

    assert_equal "1,234.56", import.reload.number_format
  end

  test "reads the October 2026 export: spaces before quoted values and transfers as two rows" do
    csv = <<~CSV
      Título, Fecha, Importe, Categoría, Subcategoría, Etiquetas, Concepto, Comercio, Cuentas, Nota
      "Mapfre España SA", 2026-10-23 00:00:00.000, -79.60€, "Gastos financieros", "Seguros", , "PAGO CON TARJETA DE TASA, SEGUROS, IMPUESTOS", , "Cuenta Mano a mano",
      "Traspaso redondeo tarjeta", 2026-10-22 00:00:00.000, -0.60€, "Traspasos", , , "TRASPASO A CUENTA", , "de Cuenta Mano a mano",
      "Traspaso redondeo tarjeta", 2026-10-22 00:00:00.000, 0.60€, "Traspasos", , , "TRASPASO DESDE CUENTA", , "a Tarjeta Repsol",
      "Adeudo mensual de tarjeta", 2026-10-05 00:00:00.000, -449.97€, "Traspasos", , , , , "de Cuenta Mano a mano a Tarjeta Repsol",
    CSV
    import = @family.imports.create!(type: "TransactionImport", raw_file_str: csv, col_sep: ",")
    Import::BankPreset.apply(import)
    import.reload.generate_rows_from_csv
    rows = import.reload.rows.ordered.to_a

    mapfre = rows.find { |row| row.name == "Mapfre España SA" }
    assert_equal "Gastos financieros:Seguros", mapfre.category
    assert_equal "Cuenta Mano a mano", mapfre.account
    assert_equal "PAGO CON TARJETA DE TASA, SEGUROS, IMPUESTOS", mapfre.notes

    sides = rows.select { |row| row.name == "Traspaso redondeo tarjeta" }.map { |row| [ row.account, row.signed_amount ] }.sort
    # signed_amount is the entry's sign: money out of an account is positive.
    assert_equal [ [ "Cuenta Mano a mano", BigDecimal("0.60") ], [ "Tarjeta Repsol", BigDecimal("-0.60") ] ], sides

    adeudo = rows.select { |row| row.name == "Adeudo mensual de tarjeta" }.map { |row| [ row.account, row.signed_amount ] }.sort
    assert_equal [ [ "Cuenta Mano a mano", BigDecimal("449.97") ], [ "Tarjeta Repsol", BigDecimal("-449.97") ] ], adeudo
    assert_equal 5, rows.size
  end

  test "leaves out what the app already has: a closed account and payroll loan instalments" do
    fake = @family.accounts.create!(name: "Cuenta Fake Nómina", owner: users(:family_admin), balance: 0, currency: "USD",
                                    accountable: Depository.new, closed_on: Date.new(2025, 12, 31))
    @family.accounts.create!(name: "Póliza Ahorro", owner: users(:family_admin), balance: 0, currency: "USD", accountable: Depository.new)
    loan = accounts(:loan)
    loan.update!(name: "Préstamo Reforma")
    loan.accountable.update!(payroll_deducted: true, payroll_deducted_since: Date.new(2026, 1, 1),
                             payroll_expense_category: categories(:food_and_drink))

    @csv = <<~CSV
      Título,Fecha,Importe,Categoría,Subcategoría,Etiquetas,Concepto,Comercio,Cuentas
      Nómina Prest,2026-10-19 15:00:00.000,140.00€,Ingresos,,,,,#{fake.name}
      Pago Préstamo,2026-10-19 16:00:00.000,-140.00€,Hogar,,,,,de #{fake.name} a Préstamo Reforma
      Inversión póliza,2026-10-19 16:00:00.000,-300.00€,Traspasos,,,,,de #{fake.name} a Póliza Ahorro
      Antiguo,2025-06-19 00:00:00.000,50.00€,Ingresos,,,,,#{fake.name}
      Café,2026-10-19 00:00:00.000,-1.50€,Comida,,,,,Póliza Ahorro
    CSV

    rows = configured_import.rows.ordered

    assert_equal [ "Antiguo", "Café", "Inversión póliza" ], rows.map(&:name).sort
    policy = rows.find { |row| row.name == "Inversión póliza" }
    assert_equal "Póliza Ahorro", policy.account
    assert_equal BigDecimal("-300.00"), policy.signed_amount, "money in"
  end

  private
    def configured_import(account: nil)
      import = @family.imports.create!(type: "TransactionImport", raw_file_str: @csv, col_sep: ",", account: account)
      Import::BankPreset.apply(import)
      import.reload.generate_rows_from_csv
      import.reload
    end
end
