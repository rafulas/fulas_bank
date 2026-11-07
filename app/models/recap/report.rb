# Fulas Bank: the written report at the top of a Recap, like Bilance's
# "Informe IA": a headline and a short paragraph about the period.
#
# As with Insight::BodyWriter, the LLM only phrases figures worked out
# beforehand (Recap#report_facts). Without a provider, without anyone in the
# family having AI enabled, or if the call fails, the same facts are put
# into sentences from the locale files, so the report never depends on an
# external service.
#
# The text is cached per period and per state of the family's movements, so
# the LLM is asked once until something changes.
class Recap::Report
  Result = Data.define(:headline, :body, :ai)

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You write the summary of a week or a month for a personal finance app.
    Rules:
    - First line: a short headline (max 6 words), no quotes.
    - Then one paragraph of 2-4 plain sentences addressed to the user as "you".
    - Use only the facts provided. Never invent numbers, dates, causes or projections.
    - Repeat monetary amounts and percentages exactly as formatted in the facts.
    - Compare with the previous period when the facts allow it.
    - No financial advice, no lists, no markdown, at most one emoji in the headline.
  PROMPT

  CACHE_VERSION = 1

  def initialize(recap)
    @recap = recap
  end

  def result
    data = Rails.cache.fetch(cache_key, expires_in: 30.days) { (llm_result || template_result).to_h }
    Result.new(**data.symbolize_keys)
  end

  private
    attr_reader :recap

    def family
      recap.family
    end

    def facts
      @facts ||= recap.report_facts
    end

    def cache_key
      [ "recap_report", CACHE_VERSION, family.id, recap.user.id, recap.kind, recap.to_param, I18n.locale,
        family.entries_version, recap.today.to_s ].join("/")
    end

    def llm_result
      return unless provider

      response = provider.chat_response(
        "Period: #{recap.kind}\nFacts: #{facts.to_json}",
        model: llm_model,
        instructions: SYSTEM_PROMPT + "- Write in the user's language (BCP 47 locale: #{I18n.locale}).\n",
        family: family
      )
      return unless response.success?

      text = response.data.messages.filter_map(&:output_text).join("\n").strip
      headline, body = text.split(/\n+/, 2).map { |part| part.to_s.strip }
      return if headline.blank? || body.blank?

      Result.new(headline: headline.delete_prefix("#").strip, body: body, ai: true)
    rescue => e
      DebugLogEntry.capture(
        category: "recaps",
        level: "warn",
        message: "Recap::Report narration failed: #{e.class}: #{e.message}",
        source: "Recap::Report",
        family: family,
        metadata: { kind: recap.kind, period: recap.to_param }
      )
      nil
    end

    def llm_model
      provider.class.effective_model
    end

    def provider
      return @provider if defined?(@provider)
      return @provider = nil unless family.users.any?(&:ai_enabled?)

      @provider = Provider::Registry.preferred_llm_provider
    end

    def template_result
      Result.new(headline: template_headline, body: template_sentences.join(" "), ai: false)
    end

    def template_headline
      key = if !recap.any_activity? then "quiet"
      elsif recap.net.negative? then "negative"
      elsif recap.spent_change&.negative? then "spent_less"
      else "positive"
      end

      I18n.t("recaps.report.headline.#{key}")
    end

    def template_sentences
      return [ I18n.t("recaps.report.no_activity", period: facts[:period]) ] unless recap.any_activity?

      sentences = [ I18n.t("recaps.report.totals", **facts.slice(:period, :spent, :income, :net)) ]

      if (change = recap.spent_change)
        key = change.negative? ? "spent_down" : "spent_up"
        sentences << I18n.t("recaps.report.#{key}", change: "#{change.abs.round} %", previous: facts[:previous_spent],
                                                     previous_period: facts[:previous_period])
      end

      if (top = facts[:top_category])
        sentences << I18n.t("recaps.report.top_category", name: top[:name], amount: top[:amount])
      end

      if (expense = facts[:biggest_expense])
        sentences << I18n.t("recaps.report.biggest_expense", name: expense[:name], amount: expense[:amount])
      end

      if (budget = facts[:budget])
        sentences << I18n.t("recaps.report.budget", budgeted: budget[:budgeted], spent: budget[:spent])
      end

      if recap.income.amount.positive?
        sentences << I18n.t("recaps.report.savings_rate", rate: facts[:savings_rate])
      end

      sentences
    end
end
