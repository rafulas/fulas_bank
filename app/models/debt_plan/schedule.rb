# Fulas Bank: month by month, how a set of loans is paid off with a strategy
# (what the "PaymentSchedule" tab of the debt reduction spreadsheet does).
#
# Every month, each loan accrues its interest and gets its usual payment.
# Then the extra money goes to the loans in the strategy's order, the first
# one still owing taking all it can:
# - the fixed monthly extra (`monthly_extra`);
# - the "snowball": the payments of the loans already paid off, which keep
#   going to the others instead of back to the current account (except with
#   the "no snowball" strategy);
# - the one-off contributions of that month (`extra_payments`, e.g. the
#   bonus each March), kept apart as "additional".
#
# Amounts are positive decimals in the loans' currency; rates are yearly
# percentages. It stops when everything is paid or after MAX_MONTHS.
class DebtPlan::Schedule
  STRATEGIES = %w[avalanche snowball stair_stepper table_order no_snowball custom_highest custom_lowest].freeze
  MAX_MONTHS = 600
  CENT = BigDecimal("0.005")

  # `key` identifies the loan (its account id); `order` is the custom order
  # typed by the user, used by the custom strategies.
  Loan = Data.define(:key, :name, :balance, :rate, :payment, :order)

  # One month of the schedule. `payments` and `additional` are by loan key:
  # what each loan got in total and, of that, how much came from that
  # month's one-off contributions. `balances` are after the payments.
  Month = Data.define(:number, :date, :snowball, :additional_total, :payments, :additional, :interest, :balances) do
    def total_payment
      payments.values.sum(BigDecimal(0))
    end

    def total_interest
      interest.values.sum(BigDecimal(0))
    end

    def total_balance
      balances.values.sum(BigDecimal(0))
    end
  end

  # Per loan: months to pay it off (nil if it is not paid within the
  # schedule), the month it is paid off and the interest paid.
  Result = Data.define(:loan, :months_to_pay_off, :paid_off_on, :total_interest)

  attr_reader :loans, :strategy, :start, :monthly_extra, :extra_payments

  # `start` is the month of the first payment; `extra_payments` maps the
  # first day of a month to the contributions of that month.
  def initialize(loans:, strategy:, start:, monthly_extra: 0, extra_payments: {})
    @loans = loans.select { |loan| loan.balance.to_d > CENT }
    @strategy = STRATEGIES.include?(strategy.to_s) ? strategy.to_s : STRATEGIES.first
    @start = start.beginning_of_month
    @monthly_extra = monthly_extra.to_d
    @extra_payments = extra_payments.transform_keys(&:beginning_of_month).transform_values(&:to_d)
  end

  # The loans in the order the extra money goes to them.
  def ordered_loans
    @ordered_loans ||= case strategy
    when "snowball" then loans.sort_by { |loan| [ loan.balance, -loan.rate ] }
    when "avalanche" then loans.sort_by { |loan| [ -loan.rate, loan.balance ] }
    when "stair_stepper" then loans.sort_by { |loan| [ months_left(loan), loan.balance ] }
    when "custom_highest" then loans.sort_by.with_index { |loan, index| [ -(loan.order || -Float::INFINITY), index ] }
    when "custom_lowest" then loans.sort_by.with_index { |loan, index| [ loan.order || Float::INFINITY, index ] }
    else loans
    end
  end

  def months
    @months ||= simulate
  end

  def results
    @results ||= loans.map do |loan|
      index = months.index { |month| month.balances[loan.key].zero? }
      Result.new(
        loan: loan,
        months_to_pay_off: index && index + 1,
        paid_off_on: index && months[index].date,
        total_interest: months.sum(BigDecimal(0)) { |month| month.interest.fetch(loan.key, 0) }
      )
    end
  end

  def paid_off?
    months.any? && months.last.total_balance.zero?
  end

  def payoff_date
    months.last.date if paid_off?
  end

  def total_interest
    months.sum(BigDecimal(0), &:total_interest)
  end

  def total_paid
    months.sum(BigDecimal(0), &:total_payment)
  end

  def total_balance
    loans.sum(BigDecimal(0)) { |loan| loan.balance.to_d }
  end

  private
    def snowball?
      strategy != "no_snowball"
    end

    # Months the usual payment needs to clear the balance; loans without a
    # payment go last.
    def months_left(loan)
      loan.payment.to_d.positive? ? loan.balance.to_d / loan.payment.to_d : Float::INFINITY
    end

    def simulate
      balances = loans.to_h { |loan| [ loan.key, loan.balance.to_d ] }
      freed = BigDecimal(0)
      list = []

      MAX_MONTHS.times do |index|
        break if balances.values.all?(&:zero?)

        date = start >> index
        interest = {}
        payments = Hash.new(BigDecimal(0))
        additional = Hash.new(BigDecimal(0))
        paid_this_month = []

        owing = loans.reject { |loan| balances[loan.key].zero? }
        owing.each do |loan|
          interest[loan.key] = (balances[loan.key] * loan.rate.to_d / 1200).round(2)
          balances[loan.key] += interest[loan.key]
        end

        # The usual payments. What a loan no longer needs of its payment in
        # its last month joins the snowball straight away.
        leftover = BigDecimal(0)
        owing.each do |loan|
          due = [ loan.payment.to_d, balances[loan.key] ].min
          payments[loan.key] += due
          balances[loan.key] -= due
          leftover += loan.payment.to_d - due
        end

        snowball = monthly_extra + (snowball? ? freed + leftover : 0)
        additional_total = extra_payments.fetch(date, BigDecimal(0))

        apply(snowball, balances, payments)
        additional.merge!(apply(additional_total, balances, payments))

        owing.each do |loan|
          next unless balances[loan.key] <= CENT

          balances[loan.key] = BigDecimal(0)
          paid_this_month << loan
        end
        freed += paid_this_month.sum(BigDecimal(0)) { |loan| loan.payment.to_d }

        list << Month.new(number: index + 1, date: date, snowball: snowball, additional_total: additional_total,
                          payments: payments.to_h, additional: additional.to_h, interest: interest, balances: balances.dup)
      end

      list
    end

    # Pays `amount` into the loans in order, each taking what it still owes.
    # Returns what each one got.
    def apply(amount, balances, payments)
      given = {}
      remaining = amount

      ordered_loans.each do |loan|
        break unless remaining.positive?
        next if balances[loan.key] <= CENT

        part = [ remaining, balances[loan.key] ].min
        balances[loan.key] -= part
        payments[loan.key] += part
        given[loan.key] = part
        remaining -= part
      end

      given
    end
end
