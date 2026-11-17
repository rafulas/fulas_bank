# Fulas Bank: rows as tab-separated text that a spreadsheet in Spanish pastes
# one value per cell: numbers with a decimal comma and no thousands
# separator, dates as dd/mm/aaaa, no currency signs.
module StatusReport::Tsv
  module_function

  def dump(rows)
    rows.map { |row| row.map { |cell| format_cell(cell) }.join("\t") }.join("\n")
  end

  def format_cell(cell)
    case cell
    when nil then ""
    when Date then cell.strftime("%d/%m/%Y")
    when Integer then cell.to_s
    when Numeric then format_number(cell)
    else cell.to_s.gsub(/[\t\r\n]+/, " ")
    end
  end

  def format_number(number)
    decimal = number.to_d.round(2)
    text = decimal.frac.zero? ? decimal.to_i.to_s : format("%.2f", decimal)
    text.tr(".", ",")
  end
end
