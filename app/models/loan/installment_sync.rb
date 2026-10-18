# Fulas Bank: the loan account is the one place a loan is kept. Its monthly
# instalment becomes a recurring movement of type «Préstamo» that the app
# creates and keeps in step with the loan — amount, payment day and last
# payment — so Planes, Recurrentes and the Forecast all show it without the
# user entering it twice.
#
# A recurring the user had already made for it (an active «Préstamo» of the
# same amount, within 3 %) is adopted instead of duplicated. When the loan is
# paid off, or loses its instalment, the movement ends. It is paid from the
# account it already had, or else from the Forecast's main account.
class Loan::InstallmentSync
  TOLERANCE = BigDecimal("0.03")

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

    series ||= adoptable(payment)
    attributes = { loan_account_id: loan_account.id, amount: payment, expected_day_of_month: payment_day(loan),
                   bill_type: "installment" }.merge(end_attributes(loan))

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

    def adoptable(payment)
      family.recurring_transactions.where(status: "active", bill_type: "installment", loan_account_id: nil,
                                          destination_account_id: nil)
            .find { |series| (series.amount.to_d.abs - payment).abs <= payment * TOLERANCE }
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
