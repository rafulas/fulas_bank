module InsurancesHelper
  def insurance_kind_options
    Insurance::KINDS.map { |kind| [ t("insurances.kinds.#{kind}"), kind ] }
  end

  def insurance_frequency_options
    Insurance::PAYMENT_FREQUENCIES.map { |frequency| [ t("insurances.frequencies.#{frequency}"), frequency ] }
  end

  # Fulas Bank: "3 plazos · próximo 01/12/2026: 150,00 €", for a policy paid
  # in custom instalments.
  def insurance_installments_label(insurance, today: Date.current)
    count = insurance.installment_schedule.size
    label = t("insurances.installments_count", count: count)
    next_date, next_amount = insurance.next_installment(today)
    return label unless next_date

    "#{label} · #{t("insurances.next_installment", date: l(next_date, format: "%d/%m/%Y"), amount: format_money(next_amount))}"
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
    # Fulas Bank: a policy that will not be renewed shows when it ends.
    if insurance.ends_on
      return render DS::Pill.new(label: t("insurances.ends_on", date: l(insurance.ends_on, format: "%d/%m/%Y")),
                                 tone: :warning, icon: "calendar-x", marker: false, size: :sm)
    end
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

  # Fulas Bank: the colour of an instalment's status (see Insurance::Instalment).
  def insurance_payment_tone(status)
    { paid: :success, suggested: :warning, overdue: :error, upcoming: :neutral }.fetch(status, :neutral)
  end
end
