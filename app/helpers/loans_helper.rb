module LoansHelper
  # The policies Loan::Insurance knows how to charge. Listed here rather than
  # built from the constant so each one carries a translated label. A fixed
  # yearly amount comes first: it is how most lenders quote the cover.
  def loan_insurance_rate_type_options
    [
      [ t("loans.form.insurance_rate_type_fixed_amount"), Loan::Insurance::FIXED_AMOUNT ],
      [ t("loans.form.insurance_rate_type_level_term"), Loan::Insurance::LEVEL_TERM ],
      [ t("loans.form.insurance_rate_type_decreasing_life"), Loan::Insurance::DECREASING_LIFE ]
    ]
  end

  # The family's assets a loan can be linked to, grouped by kind so a car
  # loan's options read "Vehículos" and a mortgage's "Inmuebles".
  def loan_asset_account_options(family)
    Loan.linkable_asset_accounts_for(family)
      .group_by { |account| account.accountable_class.display_name }
      .transform_values { |accounts| accounts.map { |account| [ account.name, account.id ] } }
  end

  # How leveraged the loan was at drawdown, as a design-system colour. Bands are
  # Loan's; the colours are this layer's.
  def loan_leverage_band_class(band)
    {
      conservative: "text-success",
      moderate: "text-warning",
      high: "text-destructive"
    }.fetch(band, "text-secondary")
  end

  # The rate types the form offers, plus the loan's own when a provider wrote
  # one the form does not know (#100 decision 8). Without it the select has no
  # matching option, the browser submits the first one, and saving any other
  # field silently turns an "arm" loan into a fixed one.
  def loan_rate_type_options(loan)
    options = [
      [ t("loans.form.rate_type_fixed"), Loan::FIXED_RATE_TYPE ],
      [ t("loans.form.rate_type_variable"), "variable" ],
      [ t("loans.form.rate_type_adjustable"), "adjustable" ]
    ]
    return options if loan.rate_type.blank? || options.any? { |_, value| value == loan.rate_type }

    options << [ loan.rate_type.titleize, loan.rate_type ]
  end
end
