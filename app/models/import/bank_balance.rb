# Fulas Bank: the balance the bank says an account had, read from the
# statement itself. BBVA statements carry it in the «Disponible» column: the
# balance after each movement. The one after the newest movement is what the
# account should hold once the statement is imported.
#
# Only for statements of one account (the account chosen for the import):
# a file with several accounts has no single balance to compare.
class Import::BankBalance
  HEADERS = [ "disponible", "saldo", "saldo disponible", "saldo contable" ].freeze

  Result = Data.define(:date, :amount)

  def self.detect(import)
    new(import).detect
  end

  def initialize(import)
    @import = import
  end

  def detect
    return unless import.is_a?(TransactionImport) && import.account.present?
    return if balance_header.nil? || import.date_col_label.blank?

    dated = import.csv_rows.filter_map do |row|
      date = parse_date(row[import.date_col_label])
      amount = import.csv_number(row[balance_header])
      [ date, amount ] if date && amount
    end
    return if dated.empty?

    # Several movements can share the newest day: the order of the file says
    # which came last. BBVA lists the newest first.
    newest = dated.map(&:first).max
    newest_first = dated.first.first >= dated.last.first
    same_day = dated.select { |date, _| date == newest }
    date, amount = newest_first ? same_day.first : same_day.last

    Result.new(date: date, amount: amount)
  rescue CSV::MalformedCSVError
    nil
  end

  private
    attr_reader :import

    def balance_header
      @balance_header ||= Array(import.csv_headers).compact.find do |header|
        HEADERS.include?(Import::BilanceExport.normalize(header))
      end
    end

    def parse_date(value)
      Date.strptime(value.to_s.strip, import.date_format)
    rescue ArgumentError, TypeError
      nil
    end
end
