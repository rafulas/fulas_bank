# Fulas Bank: a loan whose instalment the employer takes out of the pay (a
# staff loan, say). The money never reaches a bank account: the employer pays
# the lender. It used to be recorded in a made-up account, the «Cuenta Fake»,
# as pay coming in and the instalment going out, both the same day.
#
# With «Se descuenta de la nómina» on, the loan itself holds those two
# movements, each month on its payment day:
#
#   - the pay, as income in the category chosen (Nómina), and
#   - the instalment, as spending in the category chosen (the renovation
#     paid with the loan, for example: its cost spread over the instalments),
#     linked as the loan's payment, which brings the debt down to what the
#     schedule says is owed.
#
# They add up to nothing in the loan's own balance, which follows the
# schedule. Income and spending count as they did with the made-up account.
#
# The pairs already booked in another account (the «Cuenta Fake») can be moved
# to the loan once (#pairs_elsewhere, #move!). From the day the option is
# switched on, each month is booked by itself (#book_due!), once.
class Loan::PayrollDeduction
  # How far a pair's amount may be from the instalment, as a share of it.
  AMOUNT_TOLERANCE = BigDecimal("0.01")

  # `shared`: the income covers this instalment and others of that day (one
  # payslip line for several staff loans); moving takes only this
  # instalment's part of it.
  Pair = Data.define(:date, :income, :expense, :shared) do
    def amount
      expense.amount
    end

    def account
      expense.account
    end
  end

  # Books what is due in every payroll-deducted loan of the family. Called
  # when Inicio opens; Loan::InstallmentSync does it for Planes, Recurrentes
  # and the Forecast. Never breaks the page it is called from.
  def self.book_all!(family, today: Date.current)
    family.accounts.where(accountable_type: "Loan").includes(:accountable).each do |loan_account|
      loan = loan_account.accountable
      new(loan, today: today).book_due! if loan.payroll_deducted? && loan_account.active?
    end
  rescue StandardError => error
    DebugLogEntry.capture(category: "loans", level: "error", source: name, family: family,
                          message: "Payroll deduction booking failed: #{error.class}: #{error.message}")
  end

  attr_reader :loan, :today

  def initialize(loan, today: Date.current)
    @loan = loan
    @today = today
  end

  def account
    loan.account
  end

  def family
    account.family
  end

  def active?
    loan.payroll_deducted? && loan.payroll_deducted_since.present? && loan.payroll_expense_category.present? && account.present?
  end

  # Books each instalment due since the option was switched on that has no
  # payment yet. @return [Array<Pair>]
  def book_due!
    return [] unless active?

    due_dates.reject { |date| paid_in_month?(date) }.filter_map { |date| book!(date) }
  end

  # The instalment's days from the option's first day to today.
  def due_dates
    from = loan.payroll_deducted_since
    day = loan.payment_day || loan.start_date&.day || 1
    dates = []
    month = from.beginning_of_month

    while month <= today
      date = month.change(day: [ day, month.end_of_month.day ].min)
      dates << date if date >= from && date <= today && instalment_on(date)
      month = month.next_month
    end

    dates
  end

  # What the employer takes that month: the schedule's instalment, or the
  # one typed in for the loan. Nil once the schedule has run out.
  def instalment_on(date)
    schedule = loan.amortization_schedule
    amount = schedule ? schedule.payment_for(date)&.payment&.amount : loan.payment_amount
    amount = amount&.to_d
    amount if amount&.positive?
  end

  # Pay and instalment booked together in another account (the «Cuenta
  # Fake»): on the same day, in the same account, money in and the same money
  # out, about this loan's instalment. Not those already linked to another
  # loan. Oldest first.
  #
  # Fulas Bank: one income can also cover several instalments of that day
  # (427,54 € in, 303,57 € and 123,97 € out for two staff loans), when it is
  # exactly what goes out of that account that day. The pair then shares it.
  def pairs_elsewhere(since:)
    entries = candidate_entries(since)
    expenses = entries.select { |entry| entry.amount.positive? && instalment_like?(entry) }
    incomes = entries.select { |entry| entry.amount.negative? }.group_by { |entry| [ entry.account_id, entry.date ] }
    spent = entries.select { |entry| entry.amount.positive? }.group_by { |entry| [ entry.account_id, entry.date ] }
                   .transform_values { |list| list.sum(&:amount) }
    taken = Set.new

    expenses.sort_by(&:date).filter_map do |expense|
      key = [ expense.account_id, expense.date ]
      candidates = Array(incomes[key]).reject { |entry| taken.include?(entry.id) }

      if (income = candidates.find { |entry| entry.amount.abs == expense.amount })
        taken << income.id
        next Pair.new(date: expense.date, income: income, expense: expense, shared: false)
      end

      income = candidates.find { |entry| entry.amount.abs > expense.amount && entry.amount.abs == spent[key] }
      next unless income

      taken << income.id
      Pair.new(date: expense.date, income: income, expense: expense, shared: true)
    end
  end

  # Moves `pairs` into the loan, keeping their names and categories, and
  # records each instalment as the loan's payment. @return [Integer]
  def move!(pairs)
    sources = pairs.map(&:account).uniq

    count = Entry.transaction do
      pairs.count do |pair|
        if pair.shared
          take_share!(pair)
        else
          pair.income.update!(account: account)
        end
        pair.expense.update!(account: account)
        loan.link_payment!(pair.expense) unless Loan::PaymentLink.exists?(entry_id: pair.expense.id)
        link_to_series(pair.expense)
        true
      end
    end

    sources.each(&:sync_later)
    account.sync_later
    count
  end

  private
    def book!(date)
      amount = instalment_on(date)
      return unless amount

      Entry.transaction do
        income = account.entries.create!(
          name: I18n.t("loans.payroll_deduction.income_name", loan: account.name), date: date, amount: -amount,
          currency: account.currency, entryable: Transaction.new(category: loan.payroll_income_category)
        )
        expense = account.entries.create!(
          name: account.name, date: date, amount: amount,
          currency: account.currency, entryable: Transaction.new(category: loan.payroll_expense_category)
        )
        loan.link_payment!(expense)
        link_to_series(expense)
        Pair.new(date: date, income: income, expense: expense, shared: false)
      end
    end

    # This instalment's part of an income that covers several: a copy of the
    # income for that amount goes to the loan, and the rest stays where it was
    # (the other loans' part, which they take the same way).
    def take_share!(pair)
      income = pair.income
      part = pair.expense.amount

      account.entries.create!(
        name: income.name, date: income.date, amount: -part, currency: income.currency, notes: income.notes,
        entryable: Transaction.new(category: income.entryable.category, merchant: income.entryable.merchant)
      )
      income.update!(amount: income.amount + part)
    end

    def paid_in_month?(date)
      loan.payment_links.joins(:entry).where(entries: { date: date.beginning_of_month..date.end_of_month }).exists?
    end

    def instalment_like?(entry)
      expected = instalment_on(entry.date) || loan.payment_amount&.to_d
      expected.present? && expected.positive? && (entry.amount - expected).abs <= expected * AMOUNT_TOLERANCE
    end

    # Movements of the family's other accounts since `since`: ordinary ones
    # (not transfers), not linked to another loan.
    def candidate_entries(since)
      @candidate_entries ||= {}
      @candidate_entries[since] ||= begin
        other_loans = Loan::PaymentLink.where.not(loan_id: loan.id).select(:entry_id)
        family.entries.where(entryable_type: "Transaction")
              .where.not(account_id: account.id)
              .where(date: since..today)
              .where.not(id: other_loans)
              .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
              .where.not(transactions: { kind: Transaction::TRANSFER_KINDS })
              .where.not(transactions: { id: Transfer.select(:inflow_transaction_id) })
              .where.not(transactions: { id: Transfer.select(:outflow_transaction_id) })
              .includes(:account, :entryable)
              .to_a
      end
    end

    # The loan's recurring payment (Loan::InstallmentSync) takes the
    # instalment as paid, so Planes and Inicio show it settled.
    def link_to_series(expense)
      series = family.recurring_transactions.active.find_by(loan_account_id: account.id)
      return unless series

      SubscriptionLink.new(expense).link!(series)
    rescue StandardError => error
      # The instalment is booked either way; only Planes' tick is missing.
      Rails.logger.warn("Payroll instalment #{expense.id} not linked to its recurring payment: #{error.message}")
      nil
    end
end
