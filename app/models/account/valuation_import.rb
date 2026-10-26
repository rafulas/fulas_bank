# Fulas Bank: loads a list of dated values into an account from an Excel
# (.xlsx) or CSV file, one balance per row.
#
# For accounts whose balance is a value someone types (a savings policy, a
# pension plan, a house), not the running sum of their movements. Each row
# becomes the same kind of entry as «Nuevo saldo» (a reconciliation
# Valuation): the account is worth that amount on that day and keeps it until
# the next value.
#
# The file needs a title row with a date column («Fecha») and a value column
# («Valor», «Saldo», «Importe»…). It is read in two steps, like the RoadTrip
# import: #rows says what each line would do (new value, change an existing
# one, nothing, or an error) without writing anything, and #import! saves the
# valid lines in a single database transaction.
#
# If the file starts before the account's opening balance («Cuenta desde»),
# the opening balance moves to the first value of the file, so the account
# counts in net worth from that day. The opening balance it had stays as a
# value on its own date, so nothing that was there is lost.
class Account::ValuationImport
  class InvalidFile < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super(reason.to_s)
    end
  end

  MAX_ROWS = 5_000

  DATE_HEADER = /\A(fecha|date|d[ií]a|day)/i
  # In order of preference: a file with «Aportado» and «Valor» uses «Valor».
  VALUE_HEADERS = [ /valor|value/i, /saldo|balance/i, /total/i, /importe|amount/i ].freeze

  THOUSANDS_ONLY = /\A-?\d{1,3}(\.\d{3})+\z/
  PLAIN_DECIMAL = /\A-?\d+(\.\d+)?\z/

  Row = Struct.new(:number, :date, :amount, :raw_date, :raw_amount, :status, :previous_amount, keyword_init: true) do
    def importable?
      status.in?(%i[new update])
    end

    def error?
      !importable? && status != :unchanged
    end
  end

  attr_reader :account

  def self.supported?(account)
    !account.linked? &&
      account.classification == "asset" &&
      account.balance_type != :cash &&
      account.brokerage_cash?
  end

  def initialize(account, content)
    @account = account
    @content = content.to_s.b
  end

  # Every line of the file with what importing it would do. Raises
  # InvalidFile when the file cannot be read or has no date and value columns.
  def rows
    @rows ||= build_rows
  end

  def importable_rows
    rows.select(&:importable?).sort_by(&:date)
  end

  def error_rows
    rows.select(&:error?)
  end

  def count(status)
    rows.count { |row| row.status == status }
  end

  def first_date
    importable_rows.first&.date
  end

  def last_date
    importable_rows.last&.date
  end

  def opening_anchor
    return @opening_anchor if defined?(@opening_anchor)

    @opening_anchor = account.valuations.opening_anchor.includes(:entry).first&.entry
  end

  # The file starts before the opening balance: importing moves it back.
  def moves_opening_anchor_back?
    anchor = opening_anchor
    first = importable_rows.first
    return false if anchor.nil? || first.nil? || first.date >= anchor.date

    nothing_else_up_to?(first.date)
  end

  # The opening balance is older than the file (for instance, «Cuenta desde»
  # was moved back by hand and kept today's value). The person can choose to
  # start the account on the first value of the file instead.
  def can_start_at_first_row?
    anchor = opening_anchor
    first = importable_rows.first
    return false if anchor.nil? || first.nil? || first.date <= anchor.date

    nothing_else_up_to?(first.date)
  end

  # Saves the valid rows and returns how many. With start_at_first_row, an
  # opening balance older than the file moves forward to its first value.
  def import!(start_at_first_row: false)
    to_import = importable_rows
    return 0 if to_import.empty?

    Account.transaction do
      remaining =
        if moves_opening_anchor_back?
          move_opening_anchor_back(to_import)
        elsif start_at_first_row && can_start_at_first_row?
          opening_anchor.update!(date: to_import.first.date, amount: to_import.first.amount)
          to_import.drop(1)
        else
          to_import
        end

      remaining.each { |row| write_valuation(row.date, row.amount) }
    end

    # A full recalculation: the values can be anywhere in the account's
    # history, and the days before the opening balance are worked out from it.
    account.sync_later
    to_import.size
  end

  private
    attr_reader :content

    def xlsx?
      @xlsx
    end

    def build_rows
      header, data = split_header(parse_table)
      date_col, value_col = detect_columns(header)
      raise InvalidFile.new(:no_columns) if date_col.nil? || value_col.nil?

      data = data.reject { |cells| cells[date_col].blank? && cells[value_col].blank? }
      raise InvalidFile.new(:empty) if data.empty?
      raise InvalidFile.new(:too_many_rows) if data.size > MAX_ROWS

      amounts = data.map { |cells| cells[value_col].to_s }
      decimal_comma = !xlsx? && amounts.any? { |text| clean_number(text).include?(",") }
      thousands_dot = !xlsx? && !decimal_comma && amounts.map { |text| clean_number(text) }.reject(&:blank?).all? { |text| text.match?(THOUSANDS_ONLY) }

      rows = data.each_with_index.map do |cells, index|
        Row.new(
          number: index + 1,
          raw_date: cells[date_col].to_s.strip,
          raw_amount: cells[value_col].to_s.strip,
          date: parse_date(cells[date_col]),
          amount: parse_amount(cells[value_col], decimal_comma: decimal_comma, thousands_dot: thousands_dot)
        )
      end

      classify(rows)
    end

    def classify(rows)
      existing = account.entries.valuations.where(date: rows.filter_map(&:date)).index_by(&:date)
      seen = Set.new

      rows.each do |row|
        entry = existing[row.date]
        row.previous_amount = entry&.amount

        row.status =
          if row.date.nil?
            :invalid_date
          elsif row.amount.nil?
            :invalid_amount
          elsif row.date > Date.current
            :future_date
          elsif row.date <= Entry.min_supported_date
            :too_old
          elsif seen.include?(row.date)
            :duplicate_date
          elsif entry
            entry.amount.to_d == row.amount ? :unchanged : :update
          else
            :new
          end

        seen << row.date if row.importable? || row.status == :unchanged
      end
    end

    def parse_table
      if Import::XlsxConverter.xlsx?(content)
        @xlsx = true
        CSV.parse(Import::XlsxConverter.new(content).to_csv)
      else
        @xlsx = false
        text = utf8_text
        CSV.parse(text, col_sep: separator(text))
      end
    rescue Import::XlsxConverter::Error, CSV::MalformedCSVError, ArgumentError
      raise InvalidFile.new(:unreadable)
    end

    def utf8_text
      text = content.dup.force_encoding(Encoding::UTF_8)
      text = content.dup.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8) unless text.valid_encoding?
      text.delete_prefix("﻿")
    end

    # The separator that appears most in the first line: «;» in a CSV saved
    # by a Spanish Excel, «,» in most others.
    def separator(text)
      first_line = text.each_line.find(&:present?).to_s
      [ ";", "\t", "," ].max_by { |sep| [ first_line.count(sep), sep == "," ? 0 : 1 ] }
    end

    # A CSV may come without a title row: then the first line is already a
    # date, and the columns are the first two.
    def split_header(table)
      table = table.reject { |cells| cells.all?(&:blank?) }
      raise InvalidFile.new(:empty) if table.empty?

      first = table.first
      if !xlsx? && parse_date(first[0]).present?
        [ nil, table ]
      else
        [ first, table.drop(1) ]
      end
    end

    def detect_columns(header)
      return [ 0, 1 ] if header.nil?

      names = header.map { |name| name.to_s.strip }
      date_col = names.index { |name| name.match?(DATE_HEADER) }

      value_col = VALUE_HEADERS.lazy.filter_map do |pattern|
        names.each_index.find { |index| index != date_col && names[index].match?(pattern) }
      end.first

      if names.size == 2
        date_col ||= ([ 0, 1 ] - [ value_col ]).first
        value_col ||= ([ 0, 1 ] - [ date_col ]).first
      end

      [ date_col, value_col ]
    end

    # DD/MM/YYYY (also with - or .), DD/MM/YY and YYYY-MM-DD, with or without
    # a time after it.
    def parse_date(value)
      return value if value.is_a?(Date)

      text = value.to_s.strip.split(/[\sT]/).first.to_s
      year, month, day =
        case text
        when %r{\A(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\z}
          [ $1.to_i, $2.to_i, $3.to_i ]
        when %r{\A(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})\z}
          [ full_year($3), $2.to_i, $1.to_i ]
        else
          return
        end

      Date.new(year, month, day)
    rescue Date::Error
      nil
    end

    def full_year(text)
      year = text.to_i
      return year if text.length == 4

      year + (year <= Date.current.year % 100 ? 2000 : 1900)
    end

    # An Excel number cell arrives as «1234.56» (see Import::XlsxConverter);
    # a cell typed as text can still be «1.234,56». A CSV is read with one rule
    # for the whole column, decided from all of its values: any comma means
    # decimal comma (and dots for thousands); otherwise dots are decimals,
    # unless every value looks like «20.258» (thousands only).
    def parse_amount(value, decimal_comma:, thousands_dot:)
      text = clean_number(value.to_s)
      return if text.blank?

      negative = text.start_with?("(") && text.end_with?(")")
      text = text.delete("()")

      text =
        if xlsx?
          text.include?(",") ? text.delete(".").tr(",", ".") : text
        elsif decimal_comma
          text.delete(".").tr(",", ".")
        elsif thousands_dot
          text.delete(".")
        else
          text
        end

      return unless text.match?(PLAIN_DECIMAL)

      amount = BigDecimal(text)
      negative ? -amount : amount
    end

    def clean_number(text)
      text.gsub(/[[:space:]€$]|EUR|USD/i, "")
    end

    def nothing_else_up_to?(date)
      account.entries.where.not(id: opening_anchor.id).where("entries.date <= ?", date).none?
    end

    # The first row becomes the opening balance, and the value the opening
    # balance had stays on its old date (unless the file brings a value for
    # that day). Returns the rows still to write.
    def move_opening_anchor_back(rows)
      anchor = opening_anchor
      old_date = anchor.date
      old_amount = anchor.amount

      anchor.update!(date: rows.first.date, amount: rows.first.amount)
      write_valuation(old_date, old_amount) unless rows.any? { |row| row.date == old_date }

      rows.drop(1)
    end

    def write_valuation(date, amount)
      entry = account.entries.valuations.find_by(date: date) ||
              account.entries.build(
                name: Valuation.build_reconciliation_name(account.accountable_type),
                entryable: Valuation.new(kind: "reconciliation")
              )

      entry.assign_attributes(date: date, amount: amount, currency: account.currency)
      entry.save!
    end
end
