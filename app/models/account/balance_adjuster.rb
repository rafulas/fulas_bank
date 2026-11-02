# Fulas Bank: «Actualizar saldo» on a current account or a card works as in
# Bilance. The balance is a running total: every movement created, edited or
# deleted moves it. Typing the balance the bank shows does not pin the
# account to that figure; it writes a movement, «Ajuste de saldo», for the
# difference, on the day given (today by default). Movements added later,
# that day or after, keep adding up on top of it.
#
#   app says 1.000 €, bank says 980 €  ->  «Ajuste de saldo» of −20 €
#   then a 2 € coffee                  ->  978 €
#
# The adjustment is a transaction in the «Excluido» category: it is shown in
# the list and can be edited or deleted like any movement, but counts neither
# as income nor as expense (budgets, summaries, forecast). It is marked with
# `extra["balance_adjustment"]`. Several on the same day are one: adjusting
# twice on a day changes the one already there (and deletes it when the
# difference goes back to zero).
#
# Only for manual cash accounts (Depository, CreditCard), whose balance is the
# sum of their movements. Accounts tracked by their value (savings policies,
# funds, loans, a house) keep the dated values of Account::ReconciliationManager.
#
# Before this, a balance typed on such an account was a reconciliation
# valuation: the balance at the end of that day, whatever else that day had.
# A transfer created afterwards with that day's date changed the other
# account but not this one. Account::PinsToAdjustments turned those into
# adjustments.
class Account::BalanceAdjuster
  MARKER = "balance_adjustment".freeze

  # The same shape as Account::ReconciliationManager's result, so the
  # «Actualizar saldo» confirmation and the import balance check read either.
  Result = Struct.new(
    :success?, :old_cash_balance, :old_balance, :new_cash_balance, :new_balance, :error_message, :adjustment_amount,
    keyword_init: true
  )

  attr_reader :account

  def self.applies_to?(account)
    account.present? && !account.linked? && account.balance_type == :cash
  end

  def self.adjustment?(entry)
    entry&.transaction? && entry.entryable.extra.to_h[MARKER] == true
  end

  def self.adjustments_for(account)
    account.entries.joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
           .where("transactions.extra @> ?", { MARKER => true }.to_json)
  end

  def initialize(account)
    @account = account
  end

  # Leaves the account at `balance` at the end of `date`, with an adjustment
  # for the difference. `adjustment_amount` in the result is that difference
  # as the balance sees it (negative lowers it).
  def adjust_to(balance:, date: Date.current, dry_run: false)
    balance = balance.to_d
    date = date.to_date
    old_balance = balance_on(date)
    difference = balance - old_balance

    write_adjustment(difference, date) unless dry_run || difference.zero?

    Result.new(
      success?: true,
      old_cash_balance: old_balance, old_balance: old_balance,
      new_cash_balance: balance, new_balance: balance,
      error_message: nil, adjustment_amount: difference
    )
  rescue => e
    Result.new(success?: false, error_message: e.message)
  end

  # The balance at the end of `date` as the account's movements make it
  # (worked out afresh, not the cached balance a background sync may not
  # have caught up with yet). Zero before the account's first day.
  def balance_on(date)
    day = Balance::ForwardCalculator.new(account).calculate.select { |row| row.date <= date }.max_by(&:date)
    day ? day.balance.to_d : 0.to_d
  end

  # Writes `difference` (in balance terms) as the adjustment of `date`.
  def write_adjustment(difference, date)
    # An entry's amount is money out: for an asset a positive amount lowers
    # the balance; for a card (a debt) it raises it.
    amount = account.asset? ? -difference : difference
    existing = self.class.adjustments_for(account).where(date: date).order(:created_at).first

    if existing
      total = existing.amount + amount
      total.zero? ? existing.destroy! : existing.update!(amount: total)
    else
      account.entries.create!(
        date: date,
        name: self.class.entry_name(account.family),
        amount: amount,
        currency: account.currency,
        excluded: true,
        entryable: Transaction.new(category: excluded_category, extra: { MARKER => true })
      )
    end
  end

  def self.entry_name(family)
    I18n.t("account.balance_adjuster.name", locale: family&.locale.presence || I18n.default_locale, default: "Ajuste de saldo")
  end

  private
    def excluded_category
      account.family.categories.find_by(special: "excluded")
    end
end
