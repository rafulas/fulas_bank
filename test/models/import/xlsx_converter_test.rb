require "test_helper"

class Import::XlsxConverterTest < ActiveSupport::TestCase
  setup do
    @xlsx = file_fixture("imports/bbva.xlsx").binread
  end

  test "recognises xlsx content" do
    assert Import::XlsxConverter.xlsx?(@xlsx)
    assert_not Import::XlsxConverter.xlsx?(file_fixture("imports/valid.csv").read)
    assert_not Import::XlsxConverter.xlsx?(nil)
    assert_not Import::XlsxConverter.xlsx?("PK\x03\x04not really a zip")
  end

  test "converts the statement table to csv, skipping title rows" do
    csv = CSV.parse(Import::XlsxConverter.new(@xlsx).to_csv, headers: true)

    assert_equal [ "F.Valor", "Fecha", "Concepto", "Movimiento", "Importe", "Divisa", "Disponible", "Divisa (2)", "Observaciones" ], csv.headers
    assert_equal 3, csv.size

    first = csv.first
    assert_equal "29/09/2026", first["Fecha"]
    assert_equal "MERCADONA VALENCIA", first["Concepto"]
    assert_equal "-54.37", first["Importe"]
    assert_equal "EUR", first["Divisa"]

    assert_equal "1850", csv[1]["Importe"]
    assert_equal "27/09/2026", csv[1]["Fecha"]
    assert_equal "-1234.5", csv[2]["Importe"]
  end

  test "raises a converter error for unreadable spreadsheets" do
    assert_raises(Import::XlsxConverter::Error) do
      Import::XlsxConverter.new("PK\x03\x04broken").to_csv
    end
  end
end
