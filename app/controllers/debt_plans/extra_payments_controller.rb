# Fulas Bank: the one-off contributions of the debt plan (e.g. the bonus each
# March).
class DebtPlans::ExtraPaymentsController < ApplicationController
  def create
    plan = Current.family.debt_plan || Current.family.create_debt_plan!
    payment = plan.extra_payments.build(extra_payment_params)

    if payment.save
      redirect_to debt_plan_path, notice: t(".created")
    else
      redirect_to debt_plan_path, alert: payment.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.family.debt_plan&.extra_payments&.find(params[:id])&.destroy!
    redirect_to debt_plan_path, notice: t(".destroyed")
  end

  private
    def extra_payment_params
      params.require(:debt_plan_extra_payment).permit(:date, :amount, :name, :repeats_until)
    end
end
