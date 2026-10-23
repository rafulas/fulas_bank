require "test_helper"

class Import::BankPresetTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "configures a BBVA Excel statement" do
    csv = Import::XlsxConverter.new(file_fixture("imports/bbva.xlsx").binread).to_csv
    import = @family.imports.create!(type: "TransactionImport", raw_file_str: csv, col_sep: ",")

    result = Import::BankPreset.apply(import)
    import.reload

    assert_equal "bbva", result.key
    assert_equal "BBVA", result.bank_name
    assert_equal "Fecha", import.date_col_label
    assert_equal "Concepto", import.name_col_label
    assert_equal "Importe", import.amount_col_label
    assert_equal "Observaciones", import.notes_col_label
    assert_equal "Divisa", import.currency_col_label
    assert_equal "%d/%m/%Y", import.date_format
    assert_equal "1,234.56", import.number_format
    assert_equal "inflows_positive", import.signage_convention
  end

  test "configures a generic Spanish statement with European numbers" do
    csv = "Concepto;Fecha;Importe;Saldo\nMERCADONA;29/09/2026;-1.054,37;2.345,63\nNOMINA;28/09/2026;1.850,00;3.400,00\n"
    import = @family.imports.create!(type: "TransactionImport", raw_file_str: csv, col_sep: ";")

    result = Import::BankPreset.apply(import)
    import.reload

    assert_equal "es_generic", result.key
    assert_nil result.bank_name
    assert_equal "Fecha", import.date_col_label
    assert_equal "Concepto", import.name_col_label
    assert_equal "Importe", import.amount_col_label
    assert_equal "1.234,56", import.number_format
    assert_equal "%d/%m/%Y", import.date_format
  end

  # The Excel converter writes whole euros without decimals ("-5", "10"). A
  # statement whose newest 50+ movements are round amounts used to be read as
  # Spanish numbers, so a later "-12.34" became -1234.
  test "reads the whole statement to choose the number format" do
    round = Array.new(52) do |i|
      date = format("%02d/09/2026", (i % 28) + 1)
      "#{date},#{date},TRASPASO #{i},x,#{i.odd? ? 10 : -5},EUR,5000"
    end
    with_cents = Array.new(8) do |i|
      date = format("%02d/06/2026", i + 1)
      "#{date},#{date},COMPRA #{i},x,-12.34,EUR,4969"
    end
    csv = "F.Valor,Fecha,Concepto,Movimiento,Importe,Divisa,Disponible\n#{(round + with_cents).join("\n")}\n"
    import = @family.imports.create!(type: "TransactionImport", raw_file_str: csv, col_sep: ",", number_format: "1.234,56")

    Import::BankPreset.apply(import)
    import.reload

    assert_equal "1,234.56", import.number_format
    assert_equal BigDecimal("-12.34"), import.csv_number("-12.34")
  end

  test "uses the balance column when every amount is a round number" do
    csv = "F.Valor,Fecha,Concepto,Movimiento,Importe,Divisa,Disponible\n" \
          "02/09/2026,02/09/2026,TRASPASO,x,-50,EUR,5000.55\n" \
          "01/09/2026,01/09/2026,NOMINA,x,1850,EUR,5050.55\n"
    import = @family.imports.create!(type: "TransactionImport", raw_file_str: csv, col_sep: ",", number_format: "1.234,56")

    Import::BankPreset.apply(import)

    assert_equal "1,234.56", import.reload.number_format
  end

  test "leaves unrecognised files alone" do
    import = @family.imports.create!(type: "TransactionImport", raw_file_str: file_fixture("imports/valid.csv").read, col_sep: ",")

    assert_nil Import::BankPreset.apply(import)
    assert_nil import.reload.date_col_label
  end

  test "keeps column choices already made" do
    csv = "Concepto;Fecha;Importe\nMERCADONA;29/09/2026;-54,37\n"
    import = @family.imports.create!(type: "TransactionImport", raw_file_str: csv, col_sep: ";", name_col_label: "Fecha")

    Import::BankPreset.apply(import)

    assert_equal "Fecha", import.reload.name_col_label
  end
end
