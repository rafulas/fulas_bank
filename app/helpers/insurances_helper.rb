module InsurancesHelper
  def insurance_kind_options
    Insurance::KINDS.map { |kind| [ t("insurances.kinds.#{kind}"), kind ] }
  end

  def insurance_frequency_options
    Insurance::FREQUENCIES.keys.map { |frequency| [ t("insurances.frequencies.#{frequency}"), frequency ] }
  end

  # "Cupra Ateca (vehículo)", "Casa (vivienda)".
  def insurance_asset_options(assets)
    assets.map { |account| [ "#{account.name} (#{t("insurances.asset_types.#{account.accountable_type.underscore}")})", account.id ] }
  end

  # "47,00 € al mes", "320,00 € al año".
  def insurance_premium_label(insurance)
    return t("insurances.no_premium") unless insurance.premium_money

    t("insurances.premium_per.#{insurance.payment_frequency}", amount: format_money(insurance.premium_money))
  end

  # "Renueva el 24/10/2026", amber when it is close.
  def insurance_renewal_pill(insurance, today: Date.current)
    return unless insurance.renewal_date

    days = insurance.days_to_renewal(today)
    label = if days.zero?
      t("insurances.renews_today")
    elsif insurance.renews_soon?(today)
      t("insurances.renews_in", count: days)
    else
      t("insurances.renews_on", date: l(insurance.next_renewal(today), format: "%d/%m/%Y"))
    end

    render DS::Pill.new(label: label, tone: insurance.renews_soon?(today) ? :warning : :neutral, icon: "calendar", marker: false, size: :sm)
  end
end
