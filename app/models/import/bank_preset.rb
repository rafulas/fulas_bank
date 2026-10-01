# Recognises bank statement layouts by their column headers and pre-fills the
# import configuration (which column is the date, the amount, the
# description...), so a statement from a known bank can be imported without
# mapping columns by hand.
#
# Spanish banks export in a handful of similar layouts. BBVA is recognised
# explicitly; other statements with Spanish headers (Fecha / Concepto /
# Importe and their usual variants) get the same treatment as a generic
# Spanish bank statement. The date and number formats are detected from the
# file itself rather than assumed.
class Import::BankPreset
  Result = Data.define(:key, :bank_name)

  COLUMN_SYNONYMS = {
    date: [ "fecha", "fecha operacion", "fecha de operacion", "f operacion", "fecha valor", "f valor", "fecha contable" ],
    name: [ "concepto", "descripcion", "concepto comun", "comercio" ],
    amount: [ "importe", "importe eur", "cantidad" ],
    notes: [ "observaciones", "comentario", "concepto propio", "movimiento", "mas datos" ],
    currency: [ "divisa", "moneda" ]
  }.freeze

  # Headers that, together with the core columns, identify each bank.
  BANK_SIGNATURES = {
    "bbva" => { name: "BBVA", all: [ "f valor", "fecha", "concepto", "movimiento", "importe" ] }
  }.freeze

  class << self
    # Applies the matching preset to the import, filling only the settings
    # that are still blank. Returns a Result, or nil when nothing matched.
    def apply(import)
      new(import).apply
    end
  end

  def initialize(import)
    @import = import
  end

  def apply
    return unless import.is_a?(TransactionImport)

    headers = Array(import.csv_headers).compact
    columns = match_columns(headers)
    return unless columns.values_at(:date, :name, :amount).all?(&:present?)

    import.date_col_label ||= columns[:date]
    import.name_col_label ||= columns[:name]
    import.amount_col_label ||= columns[:amount]
    import.notes_col_label ||= columns[:notes]
    import.currency_col_label ||= columns[:currency]
    # Spanish bank statements show charges as negative amounts.
    import.signage_convention = "inflows_positive"
    import.number_format = detect_number_format(columns[:amount])
    import.date_format = detect_date_format(columns[:date])
    import.save!(validate: false)

    key, signature = detect_bank(headers)
    Result.new(key: key || "es_generic", bank_name: signature&.fetch(:name))
  rescue CSV::MalformedCSVError, ActiveRecord::RecordInvalid
    nil
  end

  private
    attr_reader :import

    def match_columns(headers)
      # First match wins: BBVA has "Divisa" for the amount and a second one
      # (renamed "Divisa (2)" by the converter) for the running balance.
      normalized = headers.each_with_object({}) { |header, map| map[normalize(header)] ||= header }

      COLUMN_SYNONYMS.transform_values do |synonyms|
        synonyms.lazy.filter_map { |synonym| normalized[synonym] }.first
      end
    end

    def detect_bank(headers)
      normalized = headers.map { |header| normalize(header) }
      BANK_SIGNATURES.find { |_key, signature| (signature[:all] - normalized).empty? }
    end

    def detect_number_format(amount_header)
      samples = column_samples(amount_header)

      if samples.any? { |value| value.match?(/,\d{1,2}\z/) } || samples.any? { |value| value.match?(/\d\.\d{3},/) }
        "1.234,56"
      elsif samples.any? { |value| value.match?(/\d,\d{3}\./) }
        "1,234.56"
      else
        # Plain values such as "-54.37" (what the Excel converter writes)
        samples.any? { |value| value.match?(/\.\d{1,2}\z/) } ? "1,234.56" : (import.number_format.presence || "1.234,56")
      end
    end

    def detect_date_format(date_header)
      samples = column_samples(date_header)
      Import.detect_date_format(samples, fallback: import.date_format.presence || "%d/%m/%Y")
    end

    def column_samples(header)
      import.csv_rows.first(50).filter_map { |row| row[header].to_s.strip.presence }
    end

    # "F.Valor" -> "f valor", "IMPORTE (€)" -> "importe", "Descripción" -> "descripcion"
    def normalize(header)
      I18n.transliterate(header.to_s)
        .downcase
        .gsub(/\(.*?\)/, " ")
        .gsub(/[^a-z0-9]+/, " ")
        .strip
    end
end
