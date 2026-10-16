# Fulas Bank: how each instalment of an insurance paid in custom instalments
# was paid (see InsurancePayment): link it to a bank charge, confirm or turn
# down the charge the app proposed, mark it paid by hand, or undo it. The
# instalment is named by its due day.
class Insurances::PaymentsController < ApplicationController
  before_action :set_payment

  def link
    entry = visible_entries.find(params[:entry_id])

    if @payment.update(entry: entry, suggested: false, paid_manually: false)
      back notice: t("insurances.payments.flash.#{action_name}")
    else
      back alert: @payment.errors.full_messages.to_sentence
    end
  end

  def confirm
    @payment.update!(suggested: false) if @payment.persisted?
    back notice: t("insurances.payments.flash.#{action_name}")
  end

  def reject
    @payment.reject_entry! if @payment.persisted?
    back notice: t("insurances.payments.flash.#{action_name}")
  end

  def mark_paid
    @payment.update!(paid_manually: true, entry: nil, suggested: false)
    back notice: t("insurances.payments.flash.#{action_name}")
  end

  # Back to not paid: the charge is unlinked and the mark removed.
  def clear
    @payment.update!(entry: nil, suggested: false, paid_manually: false) if @payment.persisted?
    back notice: t("insurances.payments.flash.#{action_name}")
  end

  private
    # Only one of the policy's instalment days.
    def set_payment
      @insurance = Current.family.insurances.find(params[:insurance_id])
      due_on = Date.iso8601(params[:due_on].to_s)
      raise ActiveRecord::RecordNotFound unless instalment_day?(due_on)

      @payment = @insurance.insurance_payments.find_or_initialize_by(due_on: due_on)
    rescue Date::Error
      raise ActiveRecord::RecordNotFound
    end

    def instalment_day?(date)
      @insurance.installment_charges_between(date..date).any?
    end

    def visible_entries
      Current.family.entries.joins(:account).merge(Account.accessible_by(Current.user))
    end

    def back(**flash)
      redirect_back_or_to insurances_path, **flash
    end
end
