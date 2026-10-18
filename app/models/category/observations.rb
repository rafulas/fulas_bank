# Fulas Bank: FlowVista-style observations — a short sentence about the
# period with its figure in large type on the right. They are worked out from
# the Resumen's own numbers (Category::Analysis), so they always agree with
# the screen:
#   - merchant: how much of the spending went to one merchant;
#   - saving: the share of income moved to savings and investments (or, with
#     no saving accounts, the share left over), against the usual 20 %;
#   - income_source: where the income came from;
#   - category_change: the main category furthest above its usual month;
#   - daily: the average spending per day.
# Each one only appears when it says something (see the thresholds).
class Category::Observations
  Observation = Data.define(:key, :text, :figure, :tone)

  SAVING_REFERENCE = 20
  MERCHANT_MIN_SHARE = 15
  CATEGORY_MIN_INCREASE = BigDecimal("0.25")

  def initialize(analysis, savings_flow: nil)
    @analysis = analysis
    @savings_flow = savings_flow
  end

  def all
    @all ||= [ merchant, saving, income_source, category_change, daily ].compact
  end

  def first(count)
    all.first(count)
  end

  def any?
    all.any?
  end

  private
    attr_reader :analysis, :savings_flow

    def merchant
      spent = analysis.spent.amount
      name, amount = analysis.merchant_totals.first
      return unless name && spent.positive?

      share = percent(amount, spent)
      return if share < MERCHANT_MIN_SHARE

      build(:merchant, t("merchant", name: name, amount: money(amount)), "#{share} %", :neutral)
    end

    def saving
      if savings_flow&.any_saving_accounts? && (share = savings_flow.share_of_income)
        share = share.round
        build(:saving, t("saving", reference: SAVING_REFERENCE, amount: money(savings_flow.net.amount)), "#{share} %",
              share >= SAVING_REFERENCE ? :positive : :warning)
      elsif analysis.income.amount.positive?
        rate = analysis.savings_rate
        build(:saving, t("left_over", reference: SAVING_REFERENCE), "#{rate} %", rate >= SAVING_REFERENCE ? :positive : :warning)
      end
    end

    def income_source
      income = analysis.income.amount
      slice = analysis.income_slices.first
      return unless slice && income.positive?

      count = analysis.income_slices.size
      build(:income_source, t("income_source", name: slice.name, count: count), "#{percent(slice.amount, income)} %", :neutral)
    end

    # The main category whose spending this month is furthest above its
    # average of the previous months (at least 25 % more).
    def category_change
      bars = analysis.month_bars
      return if bars.size < 2

      current = bars.last.spending.index_by(&:id)
      previous = bars[0...-1]
      best = current.values.filter_map do |slice|
        average = previous.sum { |bar| bar.spending.find { |other| other.id == slice.id }&.amount.to_d } / previous.size
        next unless average.positive? && slice.amount > average * (1 + CATEGORY_MIN_INCREASE)

        [ slice, slice.amount - average ]
      end.max_by(&:last)
      return unless best

      slice, increase = best
      build(:category_change, t("category_change", name: slice.name, months: previous.size), "+#{money(increase)}", :warning)
    end

    def daily
      return unless analysis.spent.amount.positive?

      build(:daily, t("daily", days: analysis.days_elapsed), money(analysis.daily_average.amount), :neutral)
    end

    def build(key, text, figure, tone)
      Observation.new(key: key, text: text, figure: figure, tone: tone)
    end

    def percent(part, whole)
      (part.to_d / whole * 100).round
    end

    def money(amount)
      Money.new(amount, analysis.currency).format(precision: 0)
    end

    def t(key, **options)
      I18n.t("category.observations.#{key}", **options)
    end
end
