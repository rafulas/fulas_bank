# Fulas Bank: the debt plan (see DebtPlan), under Préstamos. Choosing the
# strategy and the loans' settings, and seeing the resulting schedule.
class DebtPlansController < ApplicationController
  before_action :set_plan

  def show
    @loans = @plan.loan_accounts(Current.user)
    @schedule = @plan.schedule(Current.user)
    # Paying only the usual payments, for comparison.
    @baseline = @plan.schedule(Current.user, strategy: "no_snowball", with_extras: false)
    @view = params[:view] == "pending" ? "pending" : "payments"
    @payment_accounts = Current.family.accounts.accessible_by(Current.user).visible
                               .where(accountable_type: "Depository").alphabetically.to_a
    @recurring_transactions = Current.family.recurring_transactions.active.order(:name).to_a
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("loans_overviews.show.title"), loans_overview_path ], [ t(".title"), nil ] ]
  end

  def update
    @plan.assign_attributes(plan_params)
    @plan.assign_loan_settings(@plan.loan_accounts(Current.user), loan_settings_params)

    if @plan.save
      redirect_to debt_plan_path, notice: t(".saved")
    else
      redirect_to debt_plan_path, alert: @plan.errors.full_messages.to_sentence
    end
  end

  private
    def set_plan
      @plan = Current.family.debt_plan || Current.family.build_debt_plan
    end

    # The payment account is not mass-assigned: it must be one the user can
    # see, and anything else leaves the main account.
    def plan_params
      permitted = params.require(:debt_plan).permit(:strategy, :monthly_extra, :feeds_forecast)
      account_id = params.dig(:debt_plan, :account_id)
      return permitted if account_id.nil?

      permitted.merge(account: Current.family.accounts.accessible_by(Current.user).find_by(id: account_id.presence))
    end

    def loan_settings_params
      raw = params.dig(:debt_plan, :loans)
      return {} unless raw.respond_to?(:keys)

      raw.keys.to_h { |key| [ key, raw[key].permit(:order, :payment, :excluded, :recurring_transaction_id).to_h ] }
    end
end
