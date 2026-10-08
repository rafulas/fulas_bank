# Totals by category for a period, for the "Resumen" screen: one row per root
# category with the sum of its own transactions and its subcategories', and,
# for one root, the breakdown by subcategory.
#
# Amounts are signed the way people read them: expenses negative, income
# positive, in the family currency.
#
# How the special categories (see Category) are shown:
#   - Traspasos: the number of transactions moving money between own
#     accounts, whether categorized as Traspasos or matched as a transfer.
#   - Excluido: its total, shown apart because it doesn't count.
#   - Sin definir: transactions with no category (not a real category).
class Category::Summary
  include IncomeStatement::ScopedTransactionsQuery

  # Matched transfer legs between own accounts (see Transaction#kind).
  TRANSFER_KINDS = %w[funds_movement cc_payment].freeze

  # `kind` is :regular, :transfers, :excluded or :uncategorized.
  Row = Data.define(:category, :total, :count, :kind) do
    def uncategorized?
      kind == :uncategorized
    end

    def transfers?
      kind == :transfers
    end

    def excluded?
      kind == :excluded
    end
  end

  attr_reader :family, :period

  def initialize(family, period:, account_ids: nil)
    @family = family
    @period = period
    @account_ids = account_ids
  end

  # Root categories, the ones with an amount first (largest first), then the
  # rest in their order; Excluido always last.
  def rows
    @rows ||= begin
      roots = categories.select { |category| category.parent_id.nil? }
      rows = roots.map { |root| root_row(root) }
      rows << Row.new(category: Category.uncategorized, total: uncategorized_total, count: uncategorized_count, kind: :uncategorized)

      excluded, others = rows.partition(&:excluded?)
      sort_rows(others, uncategorized_after: special_root(:other)) + excluded
    end
  end

  # Total of a root category with its subcategories.
  def total_for(root)
    rows.find { |row| row.category.id == root.id }&.total || 0
  end

  # [ own row, subcategory rows ] for a root category: what was assigned to
  # the root itself, and each subcategory (largest first, then in order).
  def breakdown(root)
    own = Row.new(category: root, total: own_total(root), count: own_count(root), kind: kind_for(root))
    subs = categories.select { |category| category.parent_id == root.id }.map do |sub|
      Row.new(category: sub, total: own_total(sub), count: own_count(sub), kind: :regular)
    end

    [ own, sort_rows(subs) ]
  end

  private
    def categories
      @categories ||= family.categories.to_a
    end

    def special_root(special)
      categories.find { |category| category.special == special.to_s }
    end

    def root_row(root)
      kind = kind_for(root)
      ids = [ root.id ] + categories.select { |category| category.parent_id == root.id }.map(&:id)

      case kind
      when :transfers
        Row.new(category: root, total: 0, count: transfer_count(ids), kind: kind)
      else
        Row.new(category: root, total: ids.sum { |id| totals_by_category.dig(id, :total) || 0 }, count: ids.sum { |id| totals_by_category.dig(id, :count) || 0 }, kind: kind)
      end
    end

    def kind_for(category)
      if category.special_transfers?
        :transfers
      elsif category.special_excluded?
        :excluded
      else
        :regular
      end
    end

    def own_total(category)
      totals_by_category.dig(category.id, :total) || 0
    end

    def own_count(category)
      return transfer_count([ category.id ]) if category.special_transfers?

      totals_by_category.dig(category.id, :count) || 0
    end

    def uncategorized_total
      totals_by_category.dig(nil, :total) || 0
    end

    def uncategorized_count
      totals_by_category.dig(nil, :count) || 0
    end

    # Transactions in Traspasos plus matched transfers, each counted once.
    def transfer_count(category_ids)
      grouped_rows.select { |row| row["transfer_kind"] || category_ids.include?(row["category_id"]) }.sum { |row| row["count"] }
    end

    def sort_rows(rows, uncategorized_after: nil)
      ordered = rows.sort_by do |row|
        position = if row.uncategorized?
          (uncategorized_after&.position || 0) + 0.5
        else
          row.category.position || Float::INFINITY
        end
        [ row.total.zero? ? 1 : 0, -row.total.abs, position, row.category.name.to_s.downcase ]
      end

      # Traspasos shows a count, not an amount: keep it right after the
      # categories with an amount, as the first of the rest.
      transfers, others = ordered.partition(&:transfers?)
      with_amount, without = others.partition { |row| !row.total.zero? }
      with_amount + transfers + without
    end

    # { category_id => { total:, count: } } for what counts in each category:
    # matched transfers are left out (they show under Traspasos), and so are
    # entries excluded by hand, except those in Excluido, whose total is shown.
    def totals_by_category
      @totals_by_category ||= grouped_rows.each_with_object({}) do |row, totals|
        next if row["transfer_kind"]

        category_id = row["category_id"]
        excluded_category = excluded_category_ids.include?(category_id)
        next if row["excluded"] && !excluded_category

        bucket = totals[category_id] ||= { total: 0, count: 0 }
        bucket[:total] += -row["total"]
        bucket[:count] += row["count"]
      end
    end

    def excluded_category_ids
      @excluded_category_ids ||= categories.select(&:special_excluded?).map(&:id)
    end

    def grouped_rows
      @grouped_rows ||= ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([ query_sql, sql_params ])
      ).map do |row|
        row.merge(
          "excluded" => boolean.cast(row["excluded"]),
          "transfer_kind" => boolean.cast(row["transfer_kind"]),
          "total" => row["total"].to_d,
          "count" => row["count"].to_i
        )
      end
    end

    def boolean
      ActiveModel::Type::Boolean.new
    end

    def query_sql
      <<~SQL
        SELECT
          t.category_id,
          ae.excluded,
          (t.kind IN (#{TRANSFER_KINDS.map { |kind| "'#{kind}'" }.join(", ")})) AS transfer_kind,
          SUM(#{converted_amount_sql("t")}) AS total,
          COUNT(ae.id) AS count
        FROM transactions t
        #{entries_join_sql("t")}
        #{accounts_join_sql}
        #{exchange_rates_join_sql}
        WHERE a.family_id = :family_id
          AND a.status IN ('draft', 'active')
          AND a.exclude_from_reports = false
          AND ae.date BETWEEN :start_date AND :end_date
          AND NOT EXISTS (SELECT 1 FROM entries child WHERE child.parent_entry_id = ae.id)
          #{investment_activity_label_sql("t")}
          #{pending_providers_sql}
          #{exclude_tax_advantaged_sql}
          #{account_scope_sql}
        GROUP BY t.category_id, ae.excluded, transfer_kind
      SQL
    end

    def account_scope_sql
      @account_ids.nil? ? "" : "AND a.id IN (:account_ids)"
    end

    def sql_params
      base_sql_params(start_date: period.date_range.begin, end_date: period.date_range.end).tap do |params|
        params[:account_ids] = @account_ids.presence || [ nil ] unless @account_ids.nil?
      end
    end
end
