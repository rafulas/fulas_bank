class RecurringTransaction
  # Fulas Bank: a suggestion that is a series the user already has under
  # another name. The bank writes «Préstamo RRHH Reforma» and the series is
  # «Préstamo Reforma Vivienda»: the matcher only links movements whose name
  # it knows, so it left them alone and detection offered them again as new.
  #
  # Two series look alike when they go the same way (both money in or both
  # out), cost about the same (3 %) on about the same day of the month (3
  # days), and the active one is not tied to another account.
  #
  # The suggestion's movements are those it was detected from: same account,
  # same name or shop, about the same amount, within the last year and a
  # half. Linking them to the active series (RecurringAssignment) also
  # teaches it the bank's name, so the next ones are matched on their own.
  class Lookalike
    AMOUNT_TOLERANCE = BigDecimal("0.03")
    DAY_TOLERANCE = 3
    LOOKBACK = 18.months

    # The active series `suggestion` most looks like, or nil.
    def self.for(suggestion, among:)
      among.select { |series| alike?(suggestion, series) }
           .min_by { |series| [ day_distance(suggestion, series), (series.amount.to_d.abs - suggestion.amount.to_d.abs).abs ] }
    end

    def self.alike?(suggestion, series)
      return false if series.id == suggestion.id || series.currency != suggestion.currency
      return false if series.amount.to_d.negative? != suggestion.amount.to_d.negative?
      return false if series.account_id.present? && suggestion.account_id.present? && series.account_id != suggestion.account_id

      reference = series.amount.to_d.abs
      return false unless reference.positive?
      return false if (suggestion.amount.to_d.abs - reference).abs > reference * AMOUNT_TOLERANCE

      day_distance(suggestion, series) <= DAY_TOLERANCE
    end

    # Days between the two days of the month, across the month's end (the
    # 30th and the 1st are two days apart).
    def self.day_distance(a, b)
      distance = (a.expected_day_of_month.to_i - b.expected_day_of_month.to_i).abs
      [ distance, 31 - distance ].min
    end

    attr_reader :suggestion

    def initialize(suggestion)
      @suggestion = suggestion
    end

    # The movements the suggestion was detected from.
    def entries
      reference = suggestion.amount.to_d.abs
      tolerance = reference * AMOUNT_TOLERANCE
      name = Matcher.normalize_name(suggestion.name)

      scope = suggestion.family.entries.where(entryable_type: "Transaction", currency: suggestion.currency)
                        .where(date: (Date.current - LOOKBACK)..Date.current)
                        .includes(:entryable)
      scope = scope.where(account_id: suggestion.account_id) if suggestion.account_id.present?
      scope = suggestion.amount.to_d.negative? ? scope.where("entries.amount < 0") : scope.where("entries.amount > 0")
      scope = scope.where("ABS(entries.amount) BETWEEN ? AND ?", reference - tolerance, reference + tolerance)

      scope.to_a.select do |entry|
        (suggestion.merchant_id.present? && entry.entryable.merchant_id == suggestion.merchant_id) ||
          (name.present? && Matcher.normalize_name(entry.name) == name)
      end
    end
  end
end
