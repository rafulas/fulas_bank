# Fulas Bank: how each instalment of an insurance paid in custom instalments
# was paid (see InsurancePayment): link it to a bank charge, confirm or turn
# down the charge the app proposed, mark it paid by hand, or undo it. The
# instalment is named by its due day.
#
# From the policy's form (`from=policy`) each action answers in place
# (Turbo Stream): the
# instalments card and the policy's line in the list are redrawn, so the
# next instalment can be linked without leaving and reopening the policy.
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
      @insurance.charges_between(date..date).any?
    end

    def visible_entries
      Current.family.entries.joins(:account).merge(Account.accessible_by(Current.user))
    end

    def back(notice: nil, alert: nil)
      return redirect_back_or_to(insurances_path, notice: notice, alert: alert) unless params[:from] == "policy"

      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = notice if notice
          flash.now[:alert] = alert if alert
          @insurance.insurance_payments.reset
          render turbo_stream: [
            turbo_stream.replace(ActionView::RecordIdentifier.dom_id(@insurance, :payments),
                                 partial: "insurances/payments", locals: { insurance: @insurance }),
            turbo_stream.replace(ActionView::RecordIdentifier.dom_id(@insurance),
                                 partial: "insurances/insurance", locals: { insurance: @insurance }),
            *flash_notification_stream_items
          ]
        end
        format.html { redirect_back_or_to insurances_path, notice: notice, alert: alert }
      end
    end
end
