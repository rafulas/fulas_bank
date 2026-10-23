module TransactionsHelper
  # Fulas Bank: [plan, budget row] for the month and category a movement's
  # spending counts against, or nil when it has no budget there (or is not
  # spending: income, transfers, excluded movements).
  def transaction_budget_for(entry)
    transaction = entry.transaction
    return if entry.excluded? || entry.amount.negative? || transaction.category.nil?
    return unless transaction.counts_by_kind?

    plan = MonthPlan.new(Current.family, user: Current.user, month: entry.date)
    row = plan.budget_row_for(transaction.category)
    [ plan, row ] if row
  end

  # The recurring series (a bill, a salary, a subscription) this movement was
  # matched to, if any, for the mark in the transaction list. Uses the
  # allocations the list preloads; elsewhere it loads them.
  def entry_recurring_series(entry)
    allocation = entry.recurring_allocations.find { |candidate| candidate.recurring_occurrence.present? }
    allocation&.recurring_occurrence&.recurring_transaction
  end

  # Fulas Bank: the hover text of the 🔁 next to a movement, or nil when it
  # gets none. A payment the app matched to a series names that series. A
  # movement the user marked fixed or recurring gets it too: marking creates
  # the series from the movement, but does not match the movement to it.
  #
  # @param entry [Entry] a transaction entry, with its allocations preloaded
  # @return [String, nil]
  def entry_recurring_tooltip(entry)
    if (series = entry_recurring_series(entry))
      return t("transactions.transaction.recurring_tooltip", name: series.display_name)
    end

    case entry.entryable.try(:expense_type)
    when "fixed" then t("transactions.transaction.fixed_tooltip")
    when "recurring" then t("transactions.transaction.ending_tooltip")
    end
  end

  # Fulas Bank: the quick periods of the filter bar, FlowVista style.
  TRANSACTION_PERIODS = %w[this_month last_month last_3_months this_year last_year].freeze
  TRANSACTION_TYPES = %w[expense income transfer].freeze

  # [first day, last day] of a quick period.
  def transaction_period_range(key, today = Date.current)
    case key
    when "this_month" then [ today.beginning_of_month, today.end_of_month ]
    when "last_month" then [ today.prev_month.beginning_of_month, today.prev_month.end_of_month ]
    when "last_3_months" then [ (today << 3) + 1, today ]
    when "this_year" then [ today.beginning_of_year, today.end_of_year ]
    when "last_year" then [ today.prev_year.beginning_of_year, today.prev_year.end_of_year ]
    end
  end

  # The quick period the current dates are, "all" without dates, or
  # "custom" for any other range.
  def active_transaction_period(q, today = Date.current)
    return "all" if q[:start_date].blank? && q[:end_date].blank?

    TRANSACTION_PERIODS.find do |key|
      first, last = transaction_period_range(key, today)
      q[:start_date].to_s == first.iso8601 && q[:end_date].to_s == last.iso8601
    end || "custom"
  end

  # The list with the current filters and some of them changed (nil or []
  # removes one), for the links of the filter bar.
  def transactions_filter_path(q, **changes)
    filters = q.to_h.stringify_keys.merge(changes.stringify_keys).compact_blank
    transactions_path(q: filters.presence, per_page: params[:per_page].presence)
  end

  # "Este mes" or "01/10/2026 – 31/10/2026", for the period button.
  def transaction_period_label(q)
    key = active_transaction_period(q)
    return t("transactions.searches.bar.periods.#{key}") unless key == "custom"

    # Fulas Bank: a whole month or year, chosen in the period picker, by name.
    first = Date.iso8601(q[:start_date].to_s) if q[:start_date].present?
    last = Date.iso8601(q[:end_date].to_s) if q[:end_date].present?
    if first && last && first == first.beginning_of_month && last == first.end_of_month
      return l(first, format: "%B %Y").capitalize
    elsif first && last && first == first.beginning_of_year && last == first.end_of_year
      return first.year.to_s
    end

    [ q[:start_date], q[:end_date] ].map { |date| date.present? ? l(Date.iso8601(date), format: "%d/%m/%Y") : "…" }.join(" – ")
  rescue Date::Error
    t("transactions.searches.bar.periods.custom")
  end

  # "01/10/2026" for a date filter's badge; anything else as it came.
  def transaction_filter_date(value)
    l(Date.iso8601(value.to_s), format: "%d/%m/%Y")
  rescue Date::Error
    value
  end

  # "Cuenta" or "Cuenta · 2", for a filter button with choices made.
  def transaction_filter_label(label, values)
    count = Array(values).size
    count.zero? ? label : "#{label} · #{count}"
  end

  # @return [Array<Hash>] the filters offered above the transaction list, each
  #   with the key its partial is named for, a translated label and an icon
  def transaction_search_filters
    [
      # Fulas Bank: dates, account, category and type have their own buttons
      # in the filter bar (see transactions/searches/_form).
      { key: "amount_filter", label: t("transactions.search.filters.amount"), icon: "hash" },
      { key: "tag_filter", label: t("transactions.search.filters.tag"), icon: "tags" },
      { key: "status_filter", label: t("transactions.search.filters.status"), icon: "clock" },
      { key: "merchant_filter", label: t("transactions.search.filters.merchant"), icon: "store" },
      { key: "ai_filter", label: t("transactions.search.filters.ai"), icon: "sparkles" },
      { key: "attachment_filter", label: t("transactions.search.filters.attachment"), icon: "paperclip" }
    ]
  end

  # @param filter [Hash] one entry from transaction_search_filters
  # @return [String] the partial that renders that filter's controls
  def get_transaction_search_filter_partial_path(filter)
    "transactions/searches/filters/#{filter[:key]}"
  end

  # @return [Hash] the filter shown when the user has not picked one
  def get_default_transaction_search_filter
    transaction_search_filters[0]
  end

  # A split child is only folded under its parent when the user asked for
  # grouping and the current view is rendering grouped.
  #
  # @param entry [Entry] the entry being rendered
  # @param params_grouped [String, nil] the grouped param as it arrived
  # @return [Boolean] whether to render this entry inside its split group
  def in_split_group?(entry, params_grouped)
    entry.split_child? && Current.user.show_split_grouped? && params_grouped == "true"
  end

  # Whether the current user may annotate (e.g. re-tag) entries on this
  # account. Memoized per request so list rows don't query per row.
  def can_annotate_account?(account)
    return false unless Current.user

    @annotatable_account_ids ||= Account.annotatable_by(Current.user).pluck(:id).to_set
    @annotatable_account_ids.include?(account.id)
  end

  # ---- Transaction extra details helpers ----
  # Returns a structured hash describing extra details for a transaction.
  # Input can be a Transaction or an Entry (responds_to :transaction).
  # Structure:
  #   {
  #     kind: :simplefin | :plaid | :raw,
  #     simplefin: { payee:, description:, memo: },
  #     plaid: { original_description:, payment_channel:, transaction_code: },
  #     provider_extras: [ { key:, value:, multiline: } ],
  #       multiline marks values the view should render in a <pre> block
  #       rather than inline opposite their label.
  #     raw: String (pretty JSON) — only set for :raw, where we have no
  #       structured rendering for the provider
  #   }
  def build_transaction_extra_details(obj)
    tx = obj.respond_to?(:transaction) ? obj.transaction : obj
    return nil unless tx.respond_to?(:extra) && tx.extra.present?

    extra = tx.extra

    if extra.is_a?(Hash) && extra["simplefin"].present?
      sf = extra["simplefin"]
      simple = {
        payee: sf.is_a?(Hash) ? sf["payee"].presence : nil,
        description: sf.is_a?(Hash) ? sf["description"].presence : nil,
        memo: sf.is_a?(Hash) ? sf["memo"].presence : nil
      }.compact

      extras = []
      if sf.is_a?(Hash) && sf["extra"].is_a?(Hash) && sf["extra"].present?
        sf["extra"].each do |k, v|
          extras.concat(provider_extra_rows(provider_extra_field_label(k), v))
        end
      end

      # Same rule as the Plaid branch below. SimpleFIN always writes a pending
      # flag, so a transaction carrying nothing else would otherwise open an
      # Additional details section with no details in it.
      return nil if simple.blank? && extras.blank?

      {
        kind: :simplefin,
        simplefin: simple,
        plaid: {},
        provider_extras: extras,
        raw: nil
      }
    elsif extra.is_a?(Hash) && extra["plaid"].present?
      plaid = extra["plaid"]
      simple = {
        original_description: plaid.is_a?(Hash) ? plaid["original_description"].presence : nil,
        payment_channel: plaid.is_a?(Hash) ? plaid["payment_channel"].presence : nil,
        transaction_code: plaid.is_a?(Hash) ? plaid["transaction_code"].presence : nil
      }.compact

      extras = []
      if plaid.is_a?(Hash)
        if plaid["payment_meta"].is_a?(Hash) && plaid["payment_meta"].present?
          plaid["payment_meta"].each do |k, v|
            extras.concat(provider_extra_rows(t("transactions.show.plaid_payment_meta_label", name: provider_extra_field_label(k)), v))
          end
        end

        if plaid["counterparties"].is_a?(Array) && plaid["counterparties"].present?
          plaid["counterparties"].each_with_index do |counterparty, index|
            extras.concat(provider_extra_rows(t("transactions.show.plaid_counterparty_label", index: index + 1), counterparty))
          end
        end
      end

      # Only show Additional details when there is something beyond pending flags
      return nil if simple.blank? && extras.blank?

      {
        kind: :plaid,
        simplefin: {},
        plaid: simple,
        provider_extras: extras,
        # No raw dump: the structured rows above already cover the payload, and
        # the only fields they omit (pending, pending_transaction_id) are what
        # the pending badge communicates.
        raw: nil
      }
    else
      {
        kind: :raw,
        simplefin: {},
        plaid: {},
        provider_extras: [],
        raw: pretty_json(extra)
      }
    end
  end

  # Flatten hashes into labeled rows; pretty-print remaining nested structures.
  #
  # `key` arrives already presentable — localized by the caller, or run through
  # provider_extra_field_label here. Nothing downstream reformats it, because a
  # composed label is part translation and part provider identifier and
  # `humanize` would lowercase the translated half.
  #
  # An empty value yields no row. A row with nothing opposite its label is noise,
  # and it made the extras non-blank, which defeated the guard that keeps an
  # empty Additional details section closed.
  def provider_extra_rows(key, value, depth: 0)
    value = value.reject { |item| blank_provider_extra?(item) } if value.is_a?(Array)
    return [] if blank_provider_extra?(value)

    label = key.to_s

    case value
    when Hash
      value.flat_map do |child_key, child_value|
        child = provider_extra_field_label(child_key)
        child_label = depth.zero? ? "#{label} · #{child}" : "#{label}.#{child}"
        provider_extra_rows(child_label, child_value, depth: depth + 1)
      end
    when Array
      if value.all? { |item| !item.is_a?(Hash) && !item.is_a?(Array) }
        [ provider_extra_row(label, value.join(", ")) ]
      else
        # Pass the raw value — provider_extra_row does the single encode. Handing
        # it a pretty_json string here would re-encode it into an escaped one-liner.
        [ provider_extra_row(label, value, multiline: true) ]
      end
    else
      [ provider_extra_row(label, value) ]
    end
  end

  # Builds one row for the view. The key arrives already presentable and is not
  # reformatted here, since a composed label is part translation and part
  # provider identifier.
  #
  # @param key [String] the label to show
  # @param value [Object] the provider value
  # @param multiline [Boolean] render in a block rather than opposite the label
  # @return [Hash] a row of { key:, value:, multiline: }
  def provider_extra_row(key, value, multiline: false)
    display = if multiline || value.is_a?(Hash) || value.is_a?(Array)
      pretty_json(value)
    else
      value
    end

    {
      key: key.to_s,
      value: display,
      multiline: multiline || value.is_a?(Hash) || value.is_a?(Array)
    }
  end

  # Provider field names are schema identifiers (reference_number,
  # confidence_level), so they get a translation where we know the field and
  # `humanize` otherwise — the set is open-ended and a provider can add to it
  # without us, which is better served by a readable fallback than a missing key.
  #
  # The key becomes part of an i18n lookup, so a blank or dotted one would be read
  # as a scope rather than a field name: "" resolves to the whole
  # provider_extra_fields hash, which then rendered as the label. Those fall back
  # to the humanized key, as does any lookup that comes back as something other
  # than a string.
  def provider_extra_field_label(key)
    fallback = key.to_s.humanize
    return fallback if key.to_s.strip.empty? || key.to_s.include?(".")

    label = t("transactions.show.provider_extra_fields.#{key}", default: fallback)
    label.is_a?(String) ? label : fallback
  end

  # Nothing worth a row: nil, an empty or whitespace-only string, or an empty
  # collection. false and 0 are real values a provider meant to report, so they stay.
  #
  # @param value [Object] a provider value
  # @return [Boolean] whether the value has nothing to show
  def blank_provider_extra?(value)
    case value
    when nil then true
    when String then value.strip.empty?
    when Array, Hash then value.empty?
    else false
    end
  end

  # Provider payloads are arbitrary JSON, so anything that cannot be generated
  # falls back to its string form rather than raising in a view.
  #
  # @param value [Object] any provider value
  # @return [String] indented JSON, or the value's string form
  def pretty_json(value)
    JSON.pretty_generate(value)
  rescue StandardError
    value.to_s
  end

  # ---- Fulas Bank: movements panel and month summaries ----

  # Two weeks ago shows its dates; the other two are "last week" and "this week".
  def transactions_panel_week_label(week, index, count)
    case count - 1 - index
    when 0 then t("transactions.panel.this_week")
    when 1 then t("transactions.panel.last_week")
    else
      t("transactions.panel.week_range", from: l(week.start_date, format: "%-d %b"), to: l(week.end_date, format: "%-d %b"))
    end
  end

  # "1,8K €" above a bar: whole units under a thousand, thousands with one decimal.
  def transactions_panel_compact_amount(amount, currency)
    symbol = Money::Currency.new(currency).symbol
    if amount.abs >= 1000
      "#{number_with_precision(amount / 1000, precision: 1, strip_insignificant_zeros: true)}K #{symbol}"
    else
      "#{amount.round} #{symbol}"
    end
  end

  # A day's bar height as a share of the highest day, never so thin it vanishes.
  def transactions_panel_bar_height(total, max_total)
    return 0 unless max_total.positive?

    [ (total / max_total * 80).round(2), 4 ].max
  end

  def transactions_panel_day_title(day, currency)
    lines = day.segments.map { |segment| "#{segment.name}: #{format_money(Money.new(segment.amount, currency))}" }
    ([ l(day.date, format: :long) ] + lines).join("\n")
  end

  # The day headers of the list: "Hoy", "Ayer" or "lunes, 12 de octubre".
  def entry_group_date_label(date)
    if date == Date.current
      t("transactions.list.today")
    elsif date == Date.yesterday
      t("transactions.list.yesterday")
    else
      l(date, format: t("transactions.list.day_format"))
    end
  end
end
