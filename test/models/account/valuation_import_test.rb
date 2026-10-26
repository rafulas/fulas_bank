require "test_helper"

class Account::ValuationImportTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:other_asset)
    @account.entries.destroy_all
  end

  test "reads a Spanish CSV with a title row and decimal commas" do
    import = build_import("Fecha;Valor\n31/01/2024;18.000,00\n29/02/2024;18.250,55\n")

    assert_equal [ Date.new(2024, 1, 31), Date.new(2024, 2, 29) ], import.rows.map(&:date)
    assert_equal [ BigDecimal("18000"), BigDecimal("18250.55") ], import.rows.map(&:amount)
    assert import.rows.all? { |row| row.status == :new }
  end

  test "reads a CSV without a title row" do
    import = build_import("2024-01-31,18000\n2024-02-29,18250.55\n")

    assert_equal [ BigDecimal("18000"), BigDecimal("18250.55") ], import.rows.map(&:amount)
  end

  test "picks the value column when there are more" do
    import = build_import("Fecha;Aportado;Valor\n31/01/2024;15.000;18.000,50\n")

    assert_equal BigDecimal("18000.5"), import.rows.first.amount
  end

  # Round amounts at the top must not change how the cents below are read
  # (the mistake the bank statement import made with Excel files).
  test "reads an Excel file with round values first and keeps the cents" do
    import = build_import(file_fixture("imports/valores_poliza.xlsx").binread)

    assert_equal [ Date.new(2024, 1, 31), Date.new(2024, 2, 29), Date.new(2024, 3, 31), Date.new(2024, 4, 30) ], import.rows.map(&:date)
    assert_equal [ "18000.0", "18250.0", "18512.37", "18733.05" ], import.rows.map { |row| row.amount.to_s("F") }
  end

  test "flags rows it cannot import and keeps the rest" do
    import = build_import(<<~CSV)
      Fecha;Valor
      31/01/2024;100
      xx/01/2024;200
      29/02/2024;abc
      31/01/2024;300
      01/01/#{Date.current.year + 1};400
    CSV

    assert_equal %i[new invalid_date invalid_amount duplicate_date future_date], import.rows.map(&:status)
    assert_equal 1, import.importable_rows.size
    assert_equal 4, import.error_rows.size
  end

  test "compares with the values the account already has" do
    create_valuation(Date.new(2024, 1, 31), 100)
    create_valuation(Date.new(2024, 2, 29), 200)

    import = build_import("Fecha;Valor\n31/01/2024;100\n29/02/2024;250\n31/03/2024;300\n")

    assert_equal %i[unchanged update new], import.rows.map(&:status)
    assert_equal 200, import.rows.second.previous_amount
  end

  test "imports new values and changes existing ones without duplicating" do
    create_valuation(Date.new(2024, 2, 29), 200)

    import = build_import("Fecha;Valor\n31/01/2024;100\n29/02/2024;250\n")

    assert_difference -> { @account.entries.valuations.count }, 1 do
      assert_equal 2, import.import!
    end

    assert_equal 100, @account.entries.find_by(date: Date.new(2024, 1, 31)).amount
    assert_equal 250, @account.entries.find_by(date: Date.new(2024, 2, 29)).amount
    assert @account.entries.find_by(date: Date.new(2024, 1, 31)).entryable.reconciliation?
  end

  test "importing the same file twice changes nothing the second time" do
    content = "Fecha;Valor\n31/01/2024;100\n29/02/2024;250\n"
    build_import(content).import!

    import = build_import(content)
    assert_equal %i[unchanged unchanged], import.rows.map(&:status)
    assert_no_difference -> { @account.entries.count } do
      assert_equal 0, import.import!
    end
  end

  test "moves the opening balance back to the first value and keeps its old value" do
    anchor = create_valuation(Date.new(2026, 10, 16), 20258.55, kind: "opening_anchor")

    import = build_import("Fecha;Valor\n31/01/2024;18000\n29/02/2024;18250\n")
    assert import.moves_opening_anchor_back?

    import.import!

    assert_equal Date.new(2024, 1, 31), anchor.reload.date
    assert_equal 18000, anchor.amount
    assert_equal Date.new(2024, 1, 31), Account.find(@account.id).opening_anchor_date

    kept = @account.entries.find_by(date: Date.new(2026, 10, 16))
    assert_equal 20258.55, kept.amount.to_f
    assert kept.entryable.reconciliation?
    assert_equal 3, @account.entries.valuations.count
  end

  test "can start the account on the first value when the opening balance is older" do
    anchor = create_valuation(Date.new(2020, 1, 1), 20258.55, kind: "opening_anchor")

    import = build_import("Fecha;Valor\n31/01/2024;18000\n29/02/2024;18250\n")
    assert_not import.moves_opening_anchor_back?
    assert import.can_start_at_first_row?

    import.import!(start_at_first_row: true)

    assert_equal Date.new(2024, 1, 31), anchor.reload.date
    assert_equal 18000, anchor.amount
    assert_equal 2, @account.entries.valuations.count
  end

  test "leaves an older opening balance alone unless asked" do
    anchor = create_valuation(Date.new(2020, 1, 1), 15000, kind: "opening_anchor")

    build_import("Fecha;Valor\n31/01/2024;18000\n").import!

    assert_equal Date.new(2020, 1, 1), anchor.reload.date
    assert_equal 2, @account.entries.valuations.count
  end

  test "recalculates the account once after importing" do
    @account.expects(:sync_later).once

    build_import("Fecha;Valor\n31/01/2024;100\n29/02/2024;200\n").import!
  end

  test "rejects files without date and value columns" do
    error = assert_raises(Account::ValuationImport::InvalidFile) do
      build_import("Nombre;Ciudad;País\nAna;Madrid;España\n").rows
    end

    assert_equal :no_columns, error.reason
  end

  test "only for manual accounts valued by hand" do
    assert accounts(:other_asset).valuation_import_supported?
    assert accounts(:property).valuation_import_supported?
    assert_not accounts(:depository).valuation_import_supported?
    assert_not accounts(:loan).valuation_import_supported?
    assert_not accounts(:connected).valuation_import_supported?
  end

  private
    def build_import(content)
      Account::ValuationImport.new(@account, content)
    end

    def create_valuation(date, amount, kind: "reconciliation")
      @account.entries.create!(
        date: date,
        amount: amount,
        currency: @account.currency,
        name: "Valor",
        entryable: Valuation.new(kind: kind)
      )
    end
end
