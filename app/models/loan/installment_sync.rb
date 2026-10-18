# Fulas Bank: the loan account is the one place a loan is kept. Its monthly
# instalment becomes a recurring movement of type «Préstamo» that the app
# creates and keeps in step with the loan — amount, payment day and last
# payment — so Planes, Recurrentes and the Forecast all show it without the
# user entering it twice.
#
# A recurring the user had already made for it, or one the app detected from
# the bank's charges (an active payment of the same amount, within 3 %, from
# the same account) is adopted instead of duplicated. If both already exist
# (the loan's own and one from the bank), they are merged: the one the bank's
# charges are matched to stays, linked to the loan, and the other ends. A
# movement matched to the bank's charges keeps the day the bank charges it,
# so the next ones keep matching. When the loan is paid off, or loses its
# instalment, the movement ends. It is paid from the account it already had,
# or else from the Forecast's main account.
class Loan::InstallmentSync
  TOLERANCE = BigDecimal("0.03")
  # A twin from another account must be closer still.
  CLOSE_TOLERANCE = BigDecimal("0.01")

  def initialize(family, user: nil, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  def sync!
    loan_accounts.each { |loan_account| sync_account(loan_account) }
  end

  def sync_account(loan_account)
    loan = loan_account.accountable
    series = family.recurring_transactions.find_by(loan_account_id: loan_account.id)
    payment = instalment(loan)

    if payment.nil? || loan.finished?(as_of: today) || !loan_account.active?
      series.update!(status: "ended", cancelled_on: today) if series&.active?
      return series
    end

    series ||= adoptable(payment) || same_payments(payment).min_by { |each| each.typed_installment? ? 0 : 1 }
    series = merge_twins(series, payment) if series
    attributes = { loan_account_id: loan_account.id, amount: payment, expected_day_of_month: payment_day(loan),
                   bill_type: "installment" }.merge(end_attributes(loan))
    attributes.delete(:expected_day_of_month) if series && matched_to_bank?(series)

    if series
      series.assign_attributes(attributes)
      series.status = "active" if series.ended?
      series.save! if series.changed?
      series
    else
      create_series(loan_account, payment, attributes)
    end
  end

  private
    attr_reader :family, :user, :today

    def loan_accounts
      family.accounts.where(accountable_type: "Loan").includes(:accountable)
    end

    def instalment(loan)
      amount = loan.monthly_payment&.amount || loan.payment_amount
      amount.to_d if amount.present? && amount.to_d.positive?
    end

    def payment_day(loan)
      loan.payment_day || loan.start_date&.day || 1
    end

    # Ends on the last instalment when the term is known: the first one's
    # month plus the term, or else counted from today.
    def end_attributes(loan)
      return { end_mode: "never", end_on: nil } if loan.term_months.blank?

      last = if loan.start_date
        loan.start_date.advance(months: loan.term_months - 1)
      else
        today.advance(months: loan.remaining_months(as_of: today).to_i)
      end
      { end_mode: "on_date", end_on: last.change(day: [ payment_day(loan), last.end_of_month.day ].min) }
    end

    # An active payment of about the instalment, not linked to any loan,
    # from the account the loan is paid from: one marked «Préstamo» first.
    def adoptable(payment)
      payer = payer_account
      return unless payer

      same_payments(payment, account_id: payer.id).min_by { |series| series.typed_installment? ? 0 : 1 }
    end

    # Fulas Bank: the same instalment twice (the loan's own movement and one
    # from the bank's charges, often named after the bank's concept, like
    # «Amortización préstamo»). The one with more bank charges matched to it
    # stays (the loan's own on a tie); the others end, pointing at it.
    def merge_twins(series, payment)
      twins = same_payments(payment).reject { |twin| twin.id == series.id }
      return series if twins.empty?

      keeper = ([ series ] + twins).max_by { |candidate| [ matched_count(candidate), candidate.id == series.id ? 1 : 0 ] }

      RecurringTransaction.transaction do
        ([ series ] + twins).reject { |candidate| candidate.id == keeper.id }.each do |other|
          other.update!(loan_account_id: nil, status: "ended", cancelled_on: today, replaced_by_id: keeper.id)
        end
      end

      keeper
    end

    # Active payments of about `payment` not linked to a loan: within 3 %
    # from `account_id`, or, from any account (a twin may have been made in
    # another one), within 1 %.
    def same_payments(payment, account_id: nil)
      scope = family.recurring_transactions
                    .where(status: "active", loan_account_id: nil, destination_account_id: nil)
                    .where.not(bill_type: %w[income subscription transfer])
      scope = scope.where(account_id: account_id) if account_id

      scope.select do |series|
        amount = series.amount.to_d
        tolerance = account_id ? TOLERANCE : CLOSE_TOLERANCE
        amount.positive? && (amount - payment).abs <= payment * tolerance
      end
    end

    # How many of the bank's charges are matched to the movement.
    def matched_count(series)
      RecurringAllocation.joins(:recurring_occurrence)
                         .where(recurring_occurrences: { recurring_transaction_id: series.id })
                         .where.not(entry_id: nil)
                         .count
    end

    def matched_to_bank?(series)
      matched_count(series).positive?
    end

    def create_series(loan_account, payment, attributes)
      payer = payer_account
      return unless payer

      day = attributes[:expected_day_of_month]
      next_date = today.change(day: [ day, today.end_of_month.day ].min)
      next_date = next_date.next_month.change(day: [ day, next_date.next_month.end_of_month.day ].min) if next_date < today

      family.recurring_transactions.create!(
        attributes.merge(account: payer, name: loan_account.name, currency: loan_account.currency, manual: true,
                         status: "active", category: loan_category, last_occurrence_date: next_date.prev_month,
                         next_expected_date: next_date)
      )
    end

    def payer_account
      accounts = family.accounts.visible.where.not(accountable_type: "Loan").to_a
      chosen = user&.preferences&.dig(Forecast::MAIN_ACCOUNT_PREFERENCE)
      accounts.find { |account| account.id.to_s == chosen.to_s } || Forecast.default_main_account(accounts)
    end

    def loan_category
      family.categories.find_by(name: I18n.t("models.category.defaults.loan_payments"))
    end
end
