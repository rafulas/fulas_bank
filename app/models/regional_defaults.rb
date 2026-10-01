# Instance-wide regional defaults for new families and imports.
#
# Self-hosters outside the US can set these environment variables so that new
# accounts start with their language, currency and formats instead of the
# US defaults baked into the schema. Every value is optional; anything left
# unset keeps the existing behaviour.
#
#   DEFAULT_LOCALE=es
#   DEFAULT_CURRENCY=EUR
#   DEFAULT_COUNTRY=ES
#   DEFAULT_DATE_FORMAT=%d/%m/%Y
#   DEFAULT_TIMEZONE=Europe/Madrid
#   DEFAULT_NUMBER_FORMAT=1.234,56
module RegionalDefaults
  ENV_KEYS = {
    locale: "DEFAULT_LOCALE",
    currency: "DEFAULT_CURRENCY",
    country: "DEFAULT_COUNTRY",
    date_format: "DEFAULT_DATE_FORMAT",
    timezone: "DEFAULT_TIMEZONE",
    number_format: "DEFAULT_NUMBER_FORMAT"
  }.freeze

  class << self
    def locale
      value = fetch(:locale)
      value if value && I18n.available_locales.map(&:to_s).include?(value)
    end

    def currency
      Family.normalize_currency_code(fetch(:currency))
    end

    def country
      fetch(:country)&.upcase
    end

    def date_format
      value = fetch(:date_format)
      value if value && Family::DATE_FORMATS.map(&:last).include?(value)
    end

    def timezone
      value = fetch(:timezone)
      value if value && ActiveSupport::TimeZone[value]
    end

    def number_format
      value = fetch(:number_format)
      value if value && Import::NUMBER_FORMATS.key?(value)
    end

    # Attributes to apply to a brand-new family, only for the ones configured.
    def family_attributes
      {
        locale: locale,
        currency: currency,
        country: country,
        date_format: date_format,
        timezone: timezone
      }.compact
    end

    private
      def fetch(key)
        ENV[ENV_KEYS.fetch(key)].presence&.strip
      end
  end
end
