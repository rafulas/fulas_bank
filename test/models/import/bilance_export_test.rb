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

    assert_equal [ [ "BBVA Casa a medias", BigDecimal("449.97") ], [ "Tarjeta Repsol", BigDecimal("-449.97") ] ],
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

  private
    def configured_import(account: nil)
      import = @family.imports.create!(type: "TransactionImport", raw_file_str: @csv, col_sep: ",", account: account)
      Import::BankPreset.apply(import)
      import.reload.generate_rows_from_csv
      import.reload
    end
end
