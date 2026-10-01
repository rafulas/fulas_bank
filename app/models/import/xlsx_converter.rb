# Converts the first worksheet of an Excel (.xlsx) file into CSV so it can go
# through the regular CSV import workflow.
#
# Banks such as BBVA only offer statements as Excel files, usually with a few
# title rows (account holder, IBAN, period) above the actual table. The
# converter finds the table's header row, drops the rows above it, trims empty
# columns and makes repeated header names unique (BBVA has two "Divisa"
# columns). Dates are written as DD/MM/YYYY and numbers as plain decimals with
# a period separator, so the import can detect both reliably.
#
# Only the OOXML format (.xlsx) is supported; legacy binary .xls files need to
# be re-saved as .xlsx or CSV first.
class Import::XlsxConverter
  class Error < StandardError; end

  ZIP_MAGIC = "PK\x03\x04".b.freeze
  MAX_ENTRY_SIZE = 50.megabytes
  HEADER_SCAN_ROWS = 30
  DATE_OUTPUT_FORMAT = "%d/%m/%Y".freeze

  # Built-in number format ids that Excel renders as dates or date-times.
  BUILTIN_DATE_FORMAT_IDS = ((14..22).to_a + (27..36).to_a + (45..47).to_a + (50..58).to_a).freeze

  def self.xlsx?(content)
    return false if content.blank?

    bytes = content.to_s.b
    return false unless bytes.start_with?(ZIP_MAGIC)

    with_zip(bytes) { |zip| zip.find_entry("xl/workbook.xml").present? }
  rescue Error, Zip::Error
    false
  end

  def self.with_zip(bytes)
    result = nil
    # open_buffer returns the buffer, not the block's value.
    Zip::File.open_buffer(StringIO.new(bytes)) { |zip| result = yield zip }
    result
  end

  def initialize(content)
    @bytes = content.to_s.b
  end

  # Returns the worksheet as a CSV string with a header row.
  def to_csv(col_sep: ",")
    table = header_table
    raise Error, "No table with a header row was found in the spreadsheet" if table.nil?

    CSV.generate(col_sep: col_sep) do |csv|
      table.each { |row| csv << row }
    end
  end

  private
    attr_reader :bytes

    def header_table
      rows = sheet_rows.reject { |row| row.all?(&:blank?) }
      return if rows.empty?

      header_index = detect_header_index(rows)
      return if header_index.nil?

      header = rows[header_index]
      first_col = header.index(&:present?)
      last_col = header.rindex(&:present?)

      headers = unique_headers(header[first_col..last_col])
      data = rows[(header_index + 1)..].map do |row|
        Array.new(headers.size) { |offset| row[first_col + offset] }
      end
      data.reject! { |row| row.all?(&:blank?) }
      return if data.empty?

      [ headers, *data ]
    end

    # The header row is the one with the most text cells among the first rows.
    # Title rows have one or two cells, and data rows are mostly numbers and
    # dates, so the table header stands out. Ties go to the earliest row.
    def detect_header_index(rows)
      candidates = rows.first(HEADER_SCAN_ROWS).each_with_index.map do |row, index|
        text_cells = row.count { |value| value.is_a?(String) && value.match?(/\p{L}/) }
        [ text_cells, index ]
      end

      best_count, best_index = candidates.max_by { |count, index| [ count, -index ] }
      return if best_count.to_i < 2
      return if best_index == rows.size - 1

      best_index
    end

    def unique_headers(cells)
      seen = Hash.new(0)

      cells.each_with_index.map do |cell, index|
        name = cell.to_s.strip.presence || "Columna #{index + 1}"
        seen[name.downcase] += 1
        seen[name.downcase] > 1 ? "#{name} (#{seen[name.downcase]})" : name
      end
    end

    # Cell values for the first worksheet: Strings for text, Strings formatted
    # as DD/MM/YYYY for dates, and plain decimal Strings for numbers.
    def sheet_rows
      @sheet_rows ||= self.class.with_zip(bytes) do |zip|
        @zip = zip
        doc = xml(first_sheet_path)

        doc.xpath("//sheetData/row").map do |row_node|
          row = []
          row_node.xpath("c").each_with_index do |cell, position|
            index = column_index(cell["r"]) || position
            row[index] = cell_value(cell)
          end
          row
        end
      end
    rescue Zip::Error => e
      raise Error, "Could not read the spreadsheet: #{e.message}"
    end

    def cell_value(cell)
      type = cell["t"]
      raw = cell.at_xpath("v")&.text

      case type
      when "s"
        shared_strings[raw.to_i]
      when "inlineStr"
        cell.xpath("is//t").map(&:text).join
      when "str", "e"
        raw
      when "b"
        raw == "1" ? "TRUE" : "FALSE"
      else
        return if raw.blank?

        date_style?(cell["s"].to_i) ? excel_date(raw) : plain_number(raw)
      end&.then { |value| value.is_a?(String) ? value.strip.presence : value }
    end

    def plain_number(raw)
      decimal = BigDecimal(raw)
      decimal.frac.zero? ? decimal.to_i.to_s : decimal.to_s("F")
    rescue ArgumentError
      raw
    end

    def excel_date(raw)
      serial = Float(raw)
      epoch = date1904? ? Date.new(1904, 1, 1) : Date.new(1899, 12, 30)
      (epoch + serial.floor).strftime(DATE_OUTPUT_FORMAT)
    rescue ArgumentError, TypeError
      raw
    end

    def date_style?(style_index)
      date_styles.include?(style_index)
    end

    def date_styles
      @date_styles ||= begin
        doc = xml("xl/styles.xml", optional: true)
        if doc.nil?
          Set.new
        else
          custom = doc.xpath("//numFmts/numFmt").to_h { |fmt| [ fmt["numFmtId"].to_i, fmt["formatCode"].to_s ] }

          doc.xpath("//cellXfs/xf").each_with_index.filter_map do |xf, index|
            format_id = xf["numFmtId"].to_i
            index if BUILTIN_DATE_FORMAT_IDS.include?(format_id) || date_format_code?(custom[format_id])
          end.to_set
        end
      end
    end

    # A custom format is a date when it contains day/month/year tokens once
    # quoted literals, escapes and [colour]/[locale] sections are removed.
    def date_format_code?(code)
      return false if code.blank?

      cleaned = code.gsub(/"[^"]*"/, "").gsub(/\\./, "").gsub(/\[[^\]]*\]/, "")
      cleaned.match?(/[dy]/i) || cleaned.match?(/m{3,}/i)
    end

    def shared_strings
      @shared_strings ||= begin
        doc = xml("xl/sharedStrings.xml", optional: true)
        doc ? doc.xpath("//sst/si").map { |si| si.xpath(".//t").map(&:text).join } : []
      end
    end

    def date1904?
      return @date1904 if defined?(@date1904)

      pr = xml("xl/workbook.xml").at_xpath("//workbookPr")
      @date1904 = %w[1 true].include?(pr&.[]("date1904").to_s)
    end

    def first_sheet_path
      workbook = xml("xl/workbook.xml")
      sheet = workbook.at_xpath("//sheets/sheet")
      raise Error, "The spreadsheet has no worksheets" if sheet.nil?

      rel_id = sheet["id"]
      rels = xml("xl/_rels/workbook.xml.rels", optional: true)
      target = rels&.xpath("//Relationship")&.find { |rel| rel["Id"] == rel_id }&.[]("Target")
      return "xl/worksheets/sheet1.xml" if target.blank?

      target.start_with?("/") ? target.delete_prefix("/") : File.join("xl", target)
    end

    def xml(path, optional: false)
      entry = @zip.find_entry(path)
      if entry.nil?
        return if optional

        raise Error, "Missing #{path} in spreadsheet"
      end
      raise Error, "Spreadsheet part #{path} is too large" if entry.size > MAX_ENTRY_SIZE

      Nokogiri::XML(entry.get_input_stream.read).tap(&:remove_namespaces!)
    end

    # "C12" -> 2
    def column_index(reference)
      letters = reference.to_s[/\A[A-Z]+/]
      return if letters.nil?

      letters.each_char.reduce(0) { |sum, char| sum * 26 + (char.ord - 64) } - 1
    end
end
