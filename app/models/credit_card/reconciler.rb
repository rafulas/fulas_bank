# Fulas Bank: recognises the two charges a credit card makes in the account
# it is paid from, each payment day, and files them (see CreditCard::Cycle
# and CardFinancing):
#
# 1. The statement ("Adeudo mensual de tarjeta"): the charge near the payment
#    day whose name says so, or whose amount is the statement's. It becomes a
#    payment to the card (a transfer: neither income nor spending), and the
#    card gets the matching payment in, so what it owes goes down. When the
#    card already has that payment in (imported from its own statement), the
#    two are linked instead. #status_for says whether the amount charged is
#    the one the statement expected.
# 2. The instalments ("Operación financiada con tarjeta"): one charge with the
#    instalments and fees of every financed purchase due that day. It is split
#    in two: the instalments, a payment to the card like the statement, and
#    the rest (fees and any interest), spending in the financial costs
#    category. If the charge is less than the instalments expected, it is left
#    alone: some financing is probably missing or wrong.
#
# It runs after every import and sync, and from the card's "Conciliar" button.
# A charge already filed (in a transfer, or split) is never touched again.
class CreditCard::Reconciler
  STATEMENT_WORDS = [ "adeudo mensual", "liquidacion tarjeta", "liquidacion de tarjeta", "pago tarjeta", "recibo tarjeta" ].freeze
  FINANCED_WORDS = [ "operacion financiada", "financiada con tarjeta", "pago aplazado" ].freeze
  DAYS_BEFORE = 3
  DAYS_AFTER = 5
  MONTHS_BACK = 12
  FEE_CATEGORY_NAMES = [ "comisiones bancarias", "comisiones", "intereses y comisiones", "gastos financieros" ].freeze

  # How a statement's charge went: :pending (not found yet), :matched (the
  # amount expected) or :different (found, another amount).
  Status = Data.define(:state, :entry, :expected, :charged) do
    def difference
      charged && expected ? charged - expected : nil
    end
  end

  def self.run_quietly(family)
    family.accounts.where(accountable_type: "CreditCard").includes(:accountable).sum { |card| new(card).run! }
  rescue => error
    Rails.logger.error("CreditCard::Reconciler failed for family #{family.id}: #{error.message}")
    Sentry.capture_exception(error) if defined?(Sentry)
    0
  end

  attr_reader :card, :cycle, :today

  def initialize(card, today: Date.current)
    @card = card
    @today = today
    @cycle = CreditCard::Cycle.new(card, today: today)
  end

  def payment_account
    card.credit_card.payment_account
  end

  def active?
    cycle.configured? && payment_account.present?
  end

  # Files the charges of the last year. Returns how many it filed.
  def run!
    return 0 unless active?

    count = 0
    statements.each do |statement|
      entry = statement_charge(statement)
      count += 1 if entry && link_to_card!(entry)
    end
    financed_days.each do |date, expected|
      count += 1 if split_financed!(date, expected)
    end
    count
  end

  # @param statement [CreditCard::Cycle::Statement]
  # @return [Status]
  def status_for(statement)
    expected = statement.amount
    entry = filed_statement_charge(statement) || statement_charge(statement)
    return Status.new(state: :pending, entry: nil, expected: expected, charged: nil) unless entry

    charged = entry.amount.to_d
    state = (charged - expected).abs <= 0.01 ? :matched : :different
    Status.new(state: state, entry: entry, expected: expected, charged: charged)
  end

  # Fulas Bank: the payment account's «Operación financiada» charge near
  # `date`, filed (split, or linked to the card) or not. One charge pays every
  # financed purchase due that day, with their fees.
  def financed_charge_on(date)
    return unless payment_account

    payment_account.entries.where(entryable_type: "Transaction", date: window(date), parent_entry_id: nil)
                   .where("entries.amount > 0").order(:date).to_a
                   .find { |entry| named?(entry, FINANCED_WORDS) || split_into_installments?(entry) }
  end

  # The bank's charge of a statement (see #status_for), filed or not.
  def statement_charge_for(statement)
    return unless active?

    filed_statement_charge(statement) || statement_charge(statement)
  end

  private
    def split_into_installments?(entry)
      name = I18n.t("credit_cards.reconciler.installments_name")
      entry.child_entries.any? { |child| child.name == name }
    end

    def statements
      month = cycle.statement_month_for(today)
      cycle.statements_between(month << MONTHS_BACK, month).select { |statement| statement.charged_on <= today + DAYS_AFTER }
    end

    def window(date)
      (date - DAYS_BEFORE)..(date + DAYS_AFTER)
    end

    # The payment account's charges near `date` not filed yet.
    def open_charges(date)
      payment_account.entries.where(entryable_type: "Transaction", excluded: false, date: window(date))
                     .where("entries.amount > 0").where(parent_entry_id: nil)
                     .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
                     .where.not(transactions: { id: Transfer.select(:outflow_transaction_id) })
                     .includes(:entryable).order(:date).to_a
    end

    def named?(entry, words)
      name = AssetLinker.normalize(entry.name)
      words.any? { |word| name.include?(word) }
    end

    # The statement's charge: by its name, or else by its exact amount.
    def statement_charge(statement)
      return if statement.amount.zero?

      candidates = open_charges(statement.charged_on).reject { |entry| named?(entry, FINANCED_WORDS) }
      candidates.find { |entry| named?(entry, STATEMENT_WORDS) } ||
        candidates.find { |entry| (entry.amount.to_d - statement.amount).abs <= 0.01 }
    end

    # A charge already filed as a payment to this card near the payment day.
    def filed_statement_charge(statement)
      payment_account.entries.where(entryable_type: "Transaction", date: window(statement.charged_on))
                     .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
                     .joins("INNER JOIN transfers ON transfers.outflow_transaction_id = transactions.id")
                     .joins("INNER JOIN transactions inflows ON inflows.id = transfers.inflow_transaction_id")
                     .joins("INNER JOIN entries inflow_entries ON inflow_entries.entryable_id = inflows.id AND inflow_entries.entryable_type = 'Transaction'")
                     .where(inflow_entries: { account_id: card.id })
                     .reject { |entry| named?(entry, FINANCED_WORDS) }
                     .first
    end

    # The card's payment in: the one it already has, or a new one.
    def link_to_card!(outflow)
      Transfer.transaction do
        inflow = matching_card_inflow(outflow) || card.entries.create!(
          name: I18n.t("credit_cards.reconciler.payment_name", account: payment_account.name),
          date: outflow.date, amount: -outflow.amount, currency: outflow.currency,
          entryable: Transaction.new(kind: "funds_movement")
        )
        Transfer.create!(inflow_transaction: inflow.entryable, outflow_transaction: outflow.entryable, status: "confirmed")
        inflow.entryable.update!(kind: "funds_movement")
        outflow.entryable.update!(kind: Transfer.kind_for_account(card))
      end
      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      false
    end

    def matching_card_inflow(outflow)
      card.entries.where(entryable_type: "Transaction", amount: -outflow.amount, date: (outflow.date - 4)..(outflow.date + 4))
          .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
          .where.not(transactions: { id: Transfer.select(:inflow_transaction_id) })
          .first
    end

    # { charge day => [instalments, fees] } of this card's financed purchases.
    def financed_days
      from = today << MONTHS_BACK
      card.card_financings.each_with_object(Hash.new { |hash, key| hash[key] = [ 0.to_d, 0.to_d ] }) do |financing, days|
        financing.charges(cycle).each do |charge|
          next unless charge.date.between?(from, today + DAYS_AFTER)

          days[charge.date][charge.kind == :fee ? 1 : 0] += charge.amount
        end
      end
    end

    # Splits the day's "Operación financiada" charge into the instalments (a
    # payment to the card) and the rest (fees and interest, spending).
    def split_financed!(date, (installments, _fees))
      entry = open_charges(date).find { |candidate| named?(candidate, FINANCED_WORDS) }
      return false unless entry

      amount = entry.amount.to_d
      return false if amount < installments - 0.01

      rest = amount - installments
      Entry.transaction do
        if installments.positive? && rest.positive?
          paid, cost = entry.split!([
            { name: I18n.t("credit_cards.reconciler.installments_name"), amount: installments },
            { name: I18n.t("credit_cards.reconciler.fees_name"), amount: rest, category_id: fee_category&.id }
          ])
          link_to_card!(paid)
          cost.entryable.update!(category: fee_category) if fee_category
        elsif installments.positive?
          link_to_card!(entry)
        else
          entry.entryable.update!(category: fee_category) if fee_category
        end
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def fee_category
      return @fee_category if defined?(@fee_category)

      by_name = card.family.categories.index_by { |category| AssetLinker.normalize(category.name) }
      @fee_category = FEE_CATEGORY_NAMES.lazy.map { |name| by_name[name] }.find(&:itself)
    end
end
