# Transactions exported from Bilance, a personal finance app:
#
#   Título,Fecha,Importe,Categoría,Subcategoría,Etiquetas,Concepto,Comercio,Cuentas
#   Repsol Waylet,2026-10-07 00:00:00.000,-75.29€,Transporte,Combustible,Cupra,,,Tarjeta Repsol
#   Adeudo mensual de tarjeta,2026-10-05 00:00:00.000,-449.97€,Traspasos,,,…,,de BBVA Mar&Me a Tarjeta Repsol
#
# Two things need more than a column mapping:
#
# - Transfers between the user's accounts appear once, as "de <origin> a
#   <destination>" in Cuentas, and always with a negative amount (the
#   origin's side). Imported into the destination account they must be an
#   inflow; importing every account at once, each transfer becomes both its
#   sides, money out of the origin and into the destination.
# - The category is two columns, Categoría and Subcategoría. They are joined
#   as "Categoría:Subcategoría", which the category mapping already reads as a
#   parent and its child, so "Transporte:Combustible" matches "Combustible".
class Import::BilanceExport
  HEADERS = %w[titulo fecha importe categoria subcategoria cuentas].freeze
  TRANSFER = /\Ade (.+ a .+)\z/i

  def self.match?(headers)
    normalized = Array(headers).map { |header| normalize(header) }
    (HEADERS - normalized).empty?
  end

  # "Subcategoría" -> "subcategoria"
  def self.normalize(header)
    I18n.transliterate(header.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def initialize(import)
    @import = import
    @headers = import.csv_headers.index_by { |header| self.class.normalize(header) }
  end

  # Fills the configuration for a Bilance file, replacing what the generic
  # Spanish statement guess would choose (it would take "Concepto", usually
  # empty here, as the name).
  def configure
    import.date_col_label = header("fecha")
    import.name_col_label = header("titulo")
    import.amount_col_label = header("importe")
    import.category_col_label = header("categoria")
    import.tags_col_label = header("etiquetas")
    import.notes_col_label = header("concepto")
    import.account_col_label = header("cuentas") if import.account.nil?
    import.amount_type_strategy = "signed_amount"
    import.signage_convention = "inflows_positive"
    import.number_format = "1,234.56"
    import.date_format = "%Y-%m-%d"
  end

  # Adjusts the rows built from the CSV (Import#generate_rows_from_csv):
  # subcategories and both sides of each transfer.
  # Rows are numbered again at the end: a row number is unique per import,
  # and a transfer's second side is an extra row.
  def adjust(mapped_rows, csv_rows)
    adjusted = mapped_rows.zip(csv_rows).flat_map do |row, csv_row|
      row = row.merge(category: category_for(row, csv_row))

      origin, destination = transfer_accounts(csv_row)
      next [ row ] if origin.nil? || row[:amount].blank?

      amount = BigDecimal(row[:amount]).abs

      if import.account.nil? && import.account_col_label.present?
        [
          row.merge(account: origin, amount: (-amount).to_s("F")),
          row.merge(account: destination, amount: amount.to_s("F"))
        ]
      elsif home?(destination)
        [ row.merge(amount: amount.to_s("F")) ]
      elsif home?(origin)
        [ row.merge(amount: (-amount).to_s("F")) ]
      else
        [ row ]
      end
    end

    adjusted.each.with_index(1).map { |row, index| row.merge(source_row_number: index) }
  end

  private
    attr_reader :import

    def header(key)
      @headers[key]
    end

    def category_for(row, csv_row)
      return row[:category] unless import.category_col_label == header("categoria")

      subcategory = csv_row[header("subcategoria")].to_s.strip
      subcategory.present? && row[:category].present? ? "#{row[:category]}:#{subcategory}" : row[:category]
    end

    # [origin, destination] for a transfer row, nil otherwise. Account names
    # may contain " a " themselves ("Casa a medias"), so when there is more
    # than one way to split, the one naming a known account wins.
    def transfer_accounts(csv_row)
      match = csv_row[header("cuentas")].to_s.strip.match(TRANSFER)
      return if match.nil?

      text = match[1]
      splits = text.enum_for(:scan, / a /).map do
        position = Regexp.last_match.begin(0)
        [ text[0...position].strip, text[(position + 3)..].strip ]
      end

      splits.find { |origin, destination| known?(origin) || known?(destination) } || splits.first
    end

    # The accounts the file is about: those its ordinary rows belong to, and
    # the account chosen for the import.
    def home_names
      @home_names ||= begin
        names = import.csv_rows.filter_map do |csv_row|
          value = csv_row[header("cuentas")].to_s.strip
          value unless value.blank? || value.match?(TRANSFER)
        end
        (names + [ import.account&.name ]).compact.map { |name| comparable(name) }.uniq
      end
    end

    def home?(name)
      home_names.include?(comparable(name))
    end

    def known?(name)
      home?(name)
    end

    def comparable(name)
      I18n.transliterate(name.to_s).downcase.squish
    end
end
