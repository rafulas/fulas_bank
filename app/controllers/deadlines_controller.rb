# Fulas Bank: Vencimientos y garantías (see Deadline). The list, the forms
# to add and edit, and marking one done.
class DeadlinesController < ApplicationController
  before_action :set_deadline, only: %i[edit update destroy complete reopen]

  def index
    @upcoming = Deadline::Upcoming.new(Current.family)
    @pending = Current.family.deadlines.pending.chronological.includes(:account)
    @completed = Current.family.deadlines.completed.order(completed_on: :desc).limit(10).includes(:account)
    @renewals = Current.family.insurances.active.where.not(renewal_date: nil).sort_by(&:next_renewal)
    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t(".title"), nil ] ]
  end

  def new
    account = deadline_accounts.find { |candidate| candidate.id == params[:account_id].to_s }
    kind = Deadline::KINDS.include?(params[:kind]) ? params[:kind] : Deadline.default_kind_for(account)
    @deadline = Current.family.deadlines.new(account: account, kind: kind)
  end

  def create
    @deadline = Current.family.deadlines.new(deadline_params)

    if @deadline.save
      redirect_to deadlines_path, notice: t(".success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @deadline.update(deadline_params)
      redirect_to deadlines_path, notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @deadline.destroy!
    redirect_to deadlines_path, notice: t(".success")
  end

  def complete
    @deadline.complete!
    notice = @deadline.repeats? ? t(".renewed", date: l(@deadline.due_on, format: :long)) : t(".success")
    redirect_back_or_to deadlines_path, notice: notice
  end

  def reopen
    @deadline.reopen!
    redirect_to deadlines_path, notice: t(".success")
  end

  private
    def set_deadline
      @deadline = Current.family.deadlines.find(params[:id])
    end

    def deadline_params
      permitted = params.require(:deadline).permit(:name, :kind, :due_on, :remind_days, :repeat_months, :amount, :notes, :account_id)
      permitted[:account_id] = nil unless deadline_accounts.any? { |account| account.id == permitted[:account_id].to_s }
      permitted[:repeat_months] = permitted[:repeat_months].presence
      permitted
    end

    # The accounts a deadline can be tied to: the user's visible ones.
    def deadline_accounts
      @deadline_accounts ||= accessible_accounts.visible.alphabetically.to_a
    end
    helper_method :deadline_accounts
end
