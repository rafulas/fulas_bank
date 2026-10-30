# Fulas Bank: one budget of Planes, as in Bilance: its name, the categories
# and subcategories it groups (of any main category) and its amount from the
# chosen month on.
class MonthPlans::BudgetGroupsController < ApplicationController
  before_action :set_month_budget
  before_action :set_group, only: %i[edit update destroy]

  def new
    @group = Current.family.budget_groups.new
    set_form_values
  end

  def create
    @group = Current.family.budget_groups.new
    save_group(:new)
  end

  def edit
    set_form_values
  end

  def update
    save_group(:edit)
  end

  def destroy
    @group.destroy!
    redirect_to month_plan_path(month: month_param), notice: t(".success")
  end

  private
    def set_month_budget
      @month_budget = MonthBudget.new(Current.family, user: Current.user, month: selected_month)
    end

    # Only the budgets the user sees in Planes.
    def set_group
      @group = @month_budget.find_group(params[:id]) || raise(ActiveRecord::RecordNotFound)
    end

    def save_group(template)
      attrs = params.require(:budget_group).permit(:name, :amount, category_ids: [])

      if @month_budget.assign(@group, name: attrs[:name], category_ids: attrs[:category_ids], amount: attrs[:amount])
        flash[:notice] = t("month_plans.budget_groups.saved")
        respond_to do |format|
          format.html { redirect_to month_plan_path(month: month_param) }
          format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, month_plan_path(month: month_param)) }
        end
      else
        set_form_values(chosen_ids: attrs[:category_ids], amount: attrs[:amount])
        render template, status: :unprocessable_entity
      end
    end

    # What the form shows: the categories chosen and the amount from the
    # month on (as typed, after a mistake).
    def set_form_values(chosen_ids: nil, amount: nil)
      @chosen_ids = (chosen_ids || @group.chosen_ids).map(&:to_s)
      limit = @group.persisted? ? @group.limit_for(@month_budget.month) : 0
      @amount = amount || (limit.to_s("F") if limit.positive?)
      @taken_ids = @month_budget.taken_ids(except: @group)
    end

    def selected_month
      Date.strptime(params[:month].to_s, "%Y-%m")
    rescue Date::Error
      Date.current
    end

    def month_param
      @month_budget.month.strftime("%Y-%m")
    end
end
