class LoansController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id, :subtype, :rate_type, :interest_rate, :term_months, :initial_balance, :start_date,
    :down_payment, :insurance_rate, :insurance_rate_type, :insurance_annual_amount,
    :payment_amount, :payment_day, :asset_account_id,
    { rate_changes: [ :effective_date, :rate ] }
  )

  private
    # Two loan-specific readings of the shared account form:
    #
    # * A loan is a debt, and people naturally type it as a negative figure.
    #   The app stores what is owed as a positive liability balance (the
    #   classification is what subtracts it from net worth), so a leading minus
    #   on either amount is dropped rather than recording a negative debt.
    # * The form does not ask for an opening-balance date. The original
    #   principal applies on the date the loan was formalised, and today's
    #   balance is anchored today -- so the formalisation date is the opening
    #   date. Without one, the shared default applies.
    def account_params
      permitted = super

      permitted[:balance] = unsigned(permitted[:balance]) if permitted.key?(:balance)

      accountable = permitted[:accountable_attributes]
      if accountable
        accountable[:initial_balance] = unsigned(accountable[:initial_balance]) if accountable.key?(:initial_balance)
        accountable[:payment_amount] = unsigned(accountable[:payment_amount]) if accountable.key?(:payment_amount)

        if action_name == "create" && accountable[:start_date].present? && permitted[:opening_balance_date].blank?
          permitted[:opening_balance_date] = accountable[:start_date]
        end
      end

      permitted
    end

    def unsigned(value)
      value.is_a?(String) ? value.strip.delete_prefix("-") : value
    end
end
