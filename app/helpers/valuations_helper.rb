module ValuationsHelper
  # A valuation's name as the user should read it: the app's own default
  # names (stored in English) in the user's language, anything the user
  # typed as it is.
  def valuation_entry_name(entry)
    valuation = entry.entryable
    default = Valuation::Name.new(valuation.kind, entry.account.accountable_type)
    return entry.name unless entry.name == default.to_s

    t("valuations.default_names.#{default.i18n_key}", default: entry.name)
  end
end
