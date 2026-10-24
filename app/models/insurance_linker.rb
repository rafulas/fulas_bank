# Fulas Bank: proposes the bank charge of each instalment of the insurance
# policies paid in custom instalments (see InsurancePayment), so the user
# only has to confirm it, as AssetLinker does for the car and the house.
#
# An instalment is matched with an outgoing charge a few days either side of
# its day, for about its amount (the bank rounds, or the insurer adds a
# cent), in the account the policy is charged to when it has one. A charge
# that already pays another instalment, or that the user turned down for
# this one, is not proposed.
class InsuranceLinker
  MATCH_DAYS = 7
  AMOUNT_TOLERANCE = BigDecimal("0.05")
  # Instalments this far back are looked at; older ones are history.
  LOOKBACK = 1.year

  def self.run_quietly(family)
    new(family).run!
  rescue => error
    Rails.logger.error("InsuranceLinker failed for family #{family.id}: #{error.message}")
    # Fulas Bank: visible in Ajustes › Registro de depuración, not only the log.
    DebugLogEntry.capture(
      category: "linkers", level: "error", source: "InsuranceLinker", family: family,
      message: "InsuranceLinker failed: #{error.class}: #{error.message}",
      metadata: { backtrace: Array(error.backtrace).first(5) }
    )
    Sentry.capture_exception(error) if defined?(Sentry)
    0
  end

  attr_reader :family, :today

  def initialize(family, today: Date.current)
    @family = family
    @today = today
  end

  # @return [Integer] how many instalments were given a proposal
  def run!
    count = 0
    taken = Set.new

    family.insurances.active.where(payment_frequency: Insurance::CUSTOM_FREQUENCY).find_each do |insurance|
      payments = insurance.insurance_payments.index_by(&:due_on)

      insurance.installment_charges_between((today - LOOKBACK)..(today + MATCH_DAYS)).each do |date, amount, _, _|
        payment = payments[date]
        next if payment&.paid? || payment&.entry_id.present?

        rejected = Array(payment&.rejected_entry_ids)
        match = candidates(insurance, date, amount.amount).find do |entry|
          taken.exclude?(entry.id) && rejected.exclude?(entry.id)
        end
        next unless match

        payment ||= insurance.insurance_payments.build(due_on: date)
        payment.update!(entry: match, suggested: true)
        taken << match.id
        count += 1
      end
    end

    count
  end

  # Outgoing charges of the family that could pay an instalment due on
  # `date`: around it, in the policy's account when it has one, and paying no
  # other instalment or trade. With a tolerance, only those within it of the
  # amount; the closest amount comes first, then the closest day.
  def candidates(insurance, date, amount, window: MATCH_DAYS.days, tolerance: AMOUNT_TOLERANCE)
    amount = amount.to_d
    scope = family.entries.where(entryable_type: "Transaction", excluded: false)
                  .excluding_split_parents
                  .where("entries.amount > 0")
                  .where(date: (date - window)..(date + window))
                  .where.not(id: InsurancePayment.where.not(entry_id: nil).where.not(insurance_id: insurance.id, due_on: date).select(:entry_id))
                  .where.not(id: Trade.where.not(bank_entry_id: nil).select(:bank_entry_id))
                  .includes(:account)

    scope = if insurance.payment_account_id
      scope.where(account_id: insurance.payment_account_id)
    else
      scope.joins(:account).where(accounts: { accountable_type: %w[Depository CreditCard] })
    end

    list = scope.limit(200).to_a
    list = list.select { |entry| (entry.amount.to_d - amount).abs <= amount * tolerance } if tolerance
    list.sort_by { |entry| [ amount.positive? ? (entry.amount.to_d - amount).abs / amount : 0, (entry.date - date).abs ] }
  end
end
