class RecurringTransaction
  # Rule-based first guess at what a detected charge is: a subscription (a
  # service auto-charging a card on file) or a bill (an obligation you push
  # money at). Transparent by design -- keyword lists and three heuristics, no
  # scoring -- and only a default, since Kind stays user-editable and detection
  # never reclassifies after creation.
  #
  # Category is inherited from the most common one across the cluster's
  # entries.
  #
  # Fulas Bank: a subscription is only what can be cancelled and taken up
  # again at will (Netflix, Apple, the gym). Insurance, the mortgage, a loan,
  # utilities or taxes must be paid, so they are never subscriptions, however
  # flat and small the card charge. That is decided by the series' name, in
  # Spanish too (accents ignored), and by its category in the Fulas Bank tree:
  #   1. a loan (name or category)              -> installment
  #   2. an obligation (category, or wording
  #      that doesn't name a known service)     -> bill
  #   3. a subscription service (name or cat.)  -> subscription
  #   4. a flat modest card charge, no signal   -> subscription
  #   5. anything else                          -> bill
  class Classifier
    # Services that are subscriptions essentially always.
    SUBSCRIPTION_KEYWORDS = %w[
      netflix spotify hulu disney hbo hbo\ max paramount peacock crunchyroll
      youtube prime audible kindle icloud apple.com/bill google\ one
      playstation xbox nintendo twitch patreon substack onlyfans
      dropbox github openai anthropic claude chatgpt midjourney canva adobe
      microsoft\ 365 office\ 365 notion slack zoom 1password lastpass
      bitwarden nordvpn expressvpn sirius pandora tidal deezer duolingo
      headspace calm grammarly peloton planet\ fitness la\ fitness
      grok x.ai xai
      apple amazon\ prime prime\ video google\ play dazn filmin skyshowtime
      atresplayer movistar\ plus storytel gimnasio gym basic\ fit basic-fit
      mcfit altafit vivagym viva\ gym holmes\ place anytime\ fitness
    ].freeze

    # Wording that marks classic push-payment obligations: utilities,
    # telecom, insurance, housing, taxes.
    BILL_KEYWORDS = %w[
      electric power energy gas water sewer utility utilit* insurance insur*
      mortgage rent lease loan hoa property tax comcast xfinity spectrum
      cox centurylink frontier at&t verizon t-mobile tmobile mint\ mobile
      wireless phone internet interest finance\ charge
      seguro* mapfre mutua* axa allianz generali zurich reale santalucia
      linea\ directa pelayo caser ocaso verti sanitas adeslas asisa dkv
      alquiler comunidad ibi ivtm impuesto* tasa* hacienda aeat ayuntamiento
      iberdrola endesa naturgy holaluz totalenergies electricidad luz agua*
      canal\ de\ isabel movistar vodafone orange yoigo jazztel digi masmovil
      pepephone simyo lowi telefon* fibra colegio guarderia
    ].freeze

    # Fulas Bank: a loan or a mortgage -- a fixed run of payments, then done.
    LOAN_KEYWORDS = %w[hipoteca* prestamo* financiacion leasing renting].freeze

    # Fulas Bank category names (accents dropped, lower case) that say what a
    # series is. A subcategory counts, and so does its main category.
    LOAN_CATEGORIES = [ "prestamos e intereses", "leasing" ].freeze
    OBLIGATION_CATEGORIES = [
      "gastos financieros", "seguros", "seguro del vehiculo", "seguro de hogar",
      "alquiler e hipoteca", "comunidad", "energia y suministros", "seguridad",
      "impuestos", "telefono", "educacion y colegio", "pension de alimentos y compensatoria"
    ].freeze
    SUBSCRIPTION_CATEGORIES = [
      "servicios digitales", "tv, peliculas, musica y streaming", "gimnasio",
      "libros, audiolibros y noticias"
    ].freeze

    # Buy-now-pay-later and financing: a fixed run of payments, then done.
    INSTALLMENT_KEYWORDS = %w[klarna affirm afterpay sezzle zip\ pay uplift].freeze

    # Push-payment fingerprints in raw descriptors.
    ACH_MARKERS = %w[ach web\ pmt webpmt billpay bill\ pay online\ pmt e-pay epay].freeze

    # Above this, a flat recurring charge is more likely rent-or-service
    # than a streaming plan.
    SUBSCRIPTION_AMOUNT_CEILING = BigDecimal("150")

    Result = Data.define(:bill_type, :category_id, :autopay)

    def self.classify(name:, entries:, account: nil)
      new(name: name, entries: entries, account: account).classify
    end

    # True when a series is something that must be paid (a loan, insurance,
    # a utility...), going by its name and category. Used to keep those off
    # the subscriptions page.
    def self.obligatory?(series)
      new(name: series.display_name, entries: [], category: series.category).obligatory?
    end

    # The kind a subscription should have been given instead, or nil when it
    # is a subscription after all.
    def self.kind_for_subscription(series)
      classifier = new(name: series.display_name, entries: [], category: series.category)
      if classifier.loan?
        "installment"
      elsif classifier.obligatory?
        "bill"
      end
    end

    # Fulas Bank: moves the family's subscriptions that are really loans or
    # obligations (insurance, the mortgage...) to their proper kind. Their
    # autopay and everything else stay as they are. Returns how many moved.
    def self.refile_obligations!(family)
      family.recurring_transactions.typed_subscription.includes(:merchant, category: :parent).to_a.count do |series|
        kind = kind_for_subscription(series)
        next false unless kind

        series.update_columns(bill_type: kind, updated_at: Time.current)
        true
      end
    end

    # Fulas Bank: whether a series' name or category says it is a service
    # that can be cancelled (Netflix, the gym), and it is not an obligation.
    def self.subscription_signal?(series)
      classifier = new(name: series.display_name, entries: [], category: series.category)
      !classifier.obligatory? && classifier.named_subscription?
    end

    attr_reader :name, :entries, :account

    def initialize(name:, entries:, account: nil, category: nil)
      @name = ActiveSupport::Inflector.transliterate(name.to_s).downcase
      @entries = entries
      @account = account
      @category = category
    end

    def classify
      kind =
        if loan?
          "installment"
        elsif subscription?
          "subscription"
        else
          "bill"
        end

      Result.new(
        bill_type: kind,
        category_id: modal_category_id,
        # Subscriptions and BNPL plans are auto-charges: on the list, not a
        # task.
        autopay: kind != "bill"
      )
    end

    def loan?
      matches?(INSTALLMENT_KEYWORDS) || matches?(LOAN_KEYWORDS) || category_in?(LOAN_CATEGORIES)
    end

    # A named service (Movistar Plus, a gym paid by direct debit) is still a
    # subscription even if its wording looks like a bill.
    def obligatory?
      return true if loan? || category_in?(OBLIGATION_CATEGORIES)

      (matches?(BILL_KEYWORDS) || matches?(ACH_MARKERS)) && !matches?(SUBSCRIPTION_KEYWORDS)
    end

    def named_subscription?
      matches?(SUBSCRIPTION_KEYWORDS) || category_in?(SUBSCRIPTION_CATEGORIES)
    end

    private
      def subscription?
        return false if obligatory?
        return true if matches?(SUBSCRIPTION_KEYWORDS) || category_in?(SUBSCRIPTION_CATEGORIES)

        # No name signal: an identical-to-the-cent modest charge on a credit
        # card is the shape of a card-on-file service.
        flat_amounts? && modest_amount? && credit_card_account?
      end

      # The series' category, given or the most common one of its entries.
      def category
        return @category if defined?(@category) && @category

        @category = Category.includes(:parent).find_by(id: modal_category_id) if modal_category_id
      end

      # The category or its main category is one of `names`. Only the
      # category decides, so a subcategory under "Gastos financieros" counts
      # as financial even if renamed.
      def category_in?(names)
        return false unless category

        [ category, category.parent ].compact.any? do |cat|
          names.include?(ActiveSupport::Inflector.transliterate(cat.name.to_s).downcase)
        end
      end

      # Whole words only. A substring test let "max" claim Maxwell Plumbing
      # and "gas" claim a gastropub, and a false subscription match also set
      # autopay, which removes the row from the needs-action list. A trailing
      # "*" marks a stem that may carry a suffix, so "utilit*" still reaches
      # "UTILITIES" without a bare stem matching inside unrelated words.
      def matches?(keywords)
        keywords.any? do |keyword|
          if keyword.end_with?("*")
            name.match?(/\b#{Regexp.escape(keyword.delete_suffix('*'))}\w*/)
          else
            name.match?(/\b#{Regexp.escape(keyword)}\b/)
          end
        end
      end

      def flat_amounts?
        amounts = entries.map { |entry| entry.amount.abs }
        amounts.uniq.size == 1
      end

      def modest_amount?
        entries.any? && entries.first.amount.abs <= SUBSCRIPTION_AMOUNT_CEILING
      end

      def credit_card_account?
        account&.accountable_type == "CreditCard"
      end

      def modal_category_id
        @modal_category_id ||= entries.filter_map { |entry| entry.entryable.try(:category_id) }
               .tally
               .max_by { |_category_id, count| count }
               &.first
      end
  end
end
