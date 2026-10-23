class RecurringTransaction
  # Fulas Bank: the three kinds of recurring movement the user works with,
  # on top of Sure's bill types:
  #
  #   - fixed ("Fijo"): what comes or goes every time, no question: the
  #     mortgage, a loan, the salary, a transfer to savings. It may end
  #     (a loan after its last payment), which used to be a kind of its own,
  #     "recurrente".
  #   - bill ("Recibo"): an essential service paid by direct debit: power,
  #     gas, phone, insurance. It can be switched off, to change company.
  #   - subscription ("Suscripción"): what can be cancelled and taken up
  #     again at will: Netflix, Spotify, the gym.
  #
  # Stored as the bill type: "subscription" and "bill" are themselves; every
  # other one (installment, income, transfer, other) is fixed.
  module Kind
    KINDS = %w[fixed bill subscription].freeze

    module_function

    # @param series [RecurringTransaction]
    # @return [String] one of KINDS
    def of(series)
      case series.bill_type
      when "subscription" then "subscription"
      when "bill" then "bill"
      else "fixed"
      end
    end

    # The bill type that stores `kind` for `series`: a fixed one keeps the
    # type it has when it is already fixed (income, a transfer), and is
    # otherwise an instalment plan, which may end.
    def bill_type_for(kind, series)
      case kind.to_s
      when "subscription" then "subscription"
      when "bill" then "bill"
      when "fixed"
        if series.transfer?
          "transfer"
        elsif series.typed_income? || series.amount.to_d.negative?
          "income"
        elsif of(series) == "fixed"
          series.bill_type
        else
          "installment"
        end
      end
    end

    # The kind the Classifier would give a series, from its name and
    # category: a loan or the mortgage is fixed, an obligation (insurance,
    # power, phone) a bill, a service that can be cancelled a subscription.
    def guess(series)
      return "fixed" if series.transfer? || series.typed_income? || series.amount.to_d.negative?

      classifier = Classifier.new(name: series.display_name, entries: [], category: series.category)
      if classifier.loan?
        "fixed"
      elsif classifier.obligatory?
        "bill"
      elsif Classifier.subscription_signal?(series)
        "subscription"
      else
        of(series)
      end
    end

    # Fulas Bank: files every active series under the kind its name and
    # category say (see .guess), so the user only reviews. Returns how many
    # changed.
    def reclassify!(family)
      family.recurring_transactions.where(status: %w[active paused inactive suggested])
            .includes(:merchant, category: :parent).to_a.count do |series|
        kind = guess(series)
        next false if kind == of(series)

        series.update_columns(bill_type: bill_type_for(kind, series), updated_at: Time.current)
        true
      end
    end
  end
end
