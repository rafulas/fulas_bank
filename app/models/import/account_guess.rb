# Fulas Bank: which of the user's accounts a bank statement is for, so a file
# dropped anywhere goes to the right account without asking. In order:
#
#   1. :reference - an account already imported a statement with the same
#      IBAN (Import::StatementReference).
#   2. :balance - the statement says what the account held before its first
#      movement (BBVA's "Disponible" column, minus that movement), and only
#      one account had exactly that balance on the day before. This is what
#      recognises an account the first time, when the statement starts where
#      the last import ended.
#   3. :only_one - the user has a single current account.
#
# Nothing is guessed otherwise: the user chooses.
class Import::AccountGuess
  Result = Data.define(:account, :reason)

  CASH_TYPES = %w[Depository CreditCard].freeze

  def initialize(import, accounts:)
    @import = import
    @accounts = accounts.select { |account| CASH_TYPES.include?(account.accountable_type) }
  end

  # @return [Result, nil]
  def guess
    by_reference || by_balance || only_one
  end

  private
    attr_reader :import, :accounts

    def by_reference
      reference = import.statement_reference
      return if reference.blank?

      account = accounts.find { |candidate| candidate.statement_reference == reference }
      Result.new(account: account, reason: :reference) if account
    end

    def by_balance
      opening = opening_balance
      return unless opening

      date, amount = opening
      matches = accounts.select do |account|
        before = account.balances.where(currency: account.currency).where("date < ?", date).order(date: :desc).first
        before && (before.balance.to_d - amount).abs < BigDecimal("0.01")
      end

      Result.new(account: matches.first, reason: :balance) if matches.one?
    end

    def only_one
      current = accounts.select { |account| account.accountable_type == "Depository" }
      Result.new(account: current.first, reason: :only_one) if current.one?
    end

    # [first day, balance before its first movement], from the statement's
    # running balance. Statements list the newest first, so on the oldest day
    # the last line of the file is the first movement.
    def opening_balance
      balance_header = Array(import.csv_headers).compact.find do |header|
        Import::BankBalance::HEADERS.include?(Import::BilanceExport.normalize(header))
      end
      return if balance_header.nil? || import.date_col_label.blank? || import.amount_col_label.blank?

      rows = import.csv_rows.filter_map do |row|
        date = parse_date(row[import.date_col_label])
        balance = import.csv_number(row[balance_header])
        amount = import.csv_number(row[import.amount_col_label])
        [ date, balance, amount ] if date && balance && amount
      end
      return if rows.empty?

      oldest = rows.map(&:first).min
      newest_first = rows.first.first >= rows.last.first
      same_day = rows.select { |date, _, _| date == oldest }
      date, balance, amount = newest_first ? same_day.last : same_day.first

      # The running balance comes after the movement; money in is positive.
      [ date, balance - amount ]
    rescue CSV::MalformedCSVError
      nil
    end

    def parse_date(value)
      Date.strptime(value.to_s.strip, import.date_format)
    rescue ArgumentError, TypeError
      nil
    end
end
