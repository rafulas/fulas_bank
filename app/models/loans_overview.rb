# Fulas Bank: the "Préstamos" screen, a first version. Every loan the user
# can see, with what is still owed, what was borrowed, how much has been
# repaid, its rate, its instalment and when it ends; and the totals of all of
# them. It only reads what the loan accounts already know (see Loan).
class LoansOverview
  Row = Data.define(:account, :loan, :pending, :borrowed, :paid_ratio, :monthly_payment, :payoff_date, :remaining_months) do
    def rate
      loan.interest_rate
    end

    def property
      loan.asset_account
    end
  end

  attr_reader :family, :user, :today

  def initialize(family, user:, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  def currency
    family.currency
  end

  def rows
    @rows ||= loan_accounts.map do |account|
      loan = account.accountable
      projection = loan.payoff_projection(as_of: today) if loan.amortizable?

      Row.new(
        account: account,
        loan: loan,
        pending: Money.new(account.balance.to_d.abs, account.currency),
        borrowed: (loan.original_balance if loan.original_balance.amount.positive?),
        paid_ratio: loan.balance_paid_ratio,
        monthly_payment: loan.monthly_payment || (Money.new(loan.payment_amount, account.currency) if loan.payment_amount),
        payoff_date: (projection.payoff_date if projection&.applicable?),
        remaining_months: loan.remaining_months(as_of: today)
      )
    end.sort_by { |row| -row.pending.amount }
  end

  def total_pending
    sum(rows.map(&:pending))
  end

  def total_borrowed
    sum(rows.filter_map(&:borrowed))
  end

  def total_monthly_payment
    sum(rows.filter_map(&:monthly_payment))
  end

  # Share of everything borrowed that has been repaid.
  def total_paid_ratio
    borrowed = total_borrowed.amount
    return nil unless borrowed.positive?

    (1 - total_pending.amount / borrowed).clamp(0, 1).to_f
  end

  private
    def loan_accounts
      family.accounts.accessible_by(user).visible.where(accountable_type: "Loan").includes(:accountable).alphabetically.to_a
    end

    def sum(amounts)
      Money.new(amounts.sum { |money| to_family_currency(money) }, currency)
    end

    def to_family_currency(money)
      return money.amount if money.currency.iso_code == currency

      money.exchange_to(currency).amount
    rescue Money::ConversionError
      money.amount
    end
end
