# Fulas Bank: after importing movements, does each account hold what the bank
# (or Bilance) says it holds? A difference means a movement is missing,
# repeated or has the wrong amount.
#
# For each account the import touched, the bank's balance comes from:
# - the statement, when it says it (BBVA's «Disponible», Import::BankBalance);
# - or what the user types, the balance the bank or Bilance shows today.
#   Typed balances are kept in the import's summary.
#
# The app's balance is the one the account had at the end of that day. The
# import recalculates balances in the background, so while that runs there
# is nothing to compare yet (Check#pending?).
#
# Debts (cards, loans) are kept as positive amounts in the app while banks
# often show them as negative: their balances are compared without sign.
class Import::BalanceCheck
  TOLERANCE = BigDecimal("0.01")
  SUMMARY_KEY = "bank_balances"

  Check = Data.define(:account, :date, :bank_amount, :app_amount, :source) do
    def checked?
      !bank_amount.nil?
    end

    def pending?
      checked? && app_amount.nil?
    end

    def difference
      bank_amount - app_amount if checked? && app_amount
    end

    def matched?
      difference.present? && difference.abs <= Import::BalanceCheck::TOLERANCE
    end

    def mismatched?
      difference.present? && !matched?
    end

    def adjustable?
      mismatched? && !account.linked?
    end

    def money(amount)
      Money.new(amount, account.currency) if amount
    end
  end

  attr_reader :import, :user, :today

  def initialize(import, user:, today: Date.current)
    @import = import
    @user = user
    @today = today
  end

  def available?
    import.is_a?(TransactionImport) && import.complete? && accounts.any?
  end

  def accounts
    @accounts ||= import.family.accounts.accessible_by(user)
                        .where(id: import.entries.select(:account_id))
                        .alphabetically.to_a
  end

  def checks
    @checks ||= accounts.map { |account| check_for(account) }
  end

  def check_for(account)
    date, amount, source = bank_balance(account)
    app_amount = app_balance(account, date) if amount && !recalculating?(account)

    Check.new(account: account, date: date, bank_amount: amount, app_amount: app_amount, source: source)
  end

  def recalculating?(account)
    import.family.syncing? || account.syncing?
  end

  def any_pending?
    checks.any?(&:pending?)
  end

  def mismatches
    checks.select(&:mismatched?)
  end

  # Keeps the balance the user typed for an account (today's).
  def record!(account, amount)
    balances = typed_balances.merge(account.id => { "amount" => amount.to_d.to_s, "date" => today.iso8601 })
    import.update_column(:summary, import.summary.merge(SUMMARY_KEY => balances))
    @checks = nil
  end

  # Sets the account to the bank's balance on that day, as a balance update
  # would. Returns whether it was done.
  def adjust!(account)
    check = check_for(account)
    return false unless check.adjustable?

    account.create_reconciliation(balance: check.bank_amount, date: check.date).success?
  end

  private
    def bank_balance(account)
      if (typed = typed_balances[account.id])
        [ Date.iso8601(typed["date"]), comparable(account, typed["amount"].to_d), "typed" ]
      elsif account.id == import.account_id && (detected = Import::BankBalance.detect(import))
        [ detected.date, comparable(account, detected.amount), "statement" ]
      end
    end

    def typed_balances
      import.summary.fetch(SUMMARY_KEY, {})
    end

    def comparable(account, amount)
      account.liability? ? amount.abs : amount
    end

    def app_balance(account, date)
      balance = account.balances.where(currency: account.currency).where(date: ..date).order(date: :desc).first
      balance && comparable(account, balance.end_balance.to_d)
    end
end
