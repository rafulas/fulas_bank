# Fulas Bank: rename or delete a group of rules (RuleGroup). Groups are
# created from the rule form; deleting one leaves its rules without a group.
class RuleGroupsController < ApplicationController
  before_action :set_rule_group

  def edit
  end

  def update
    if @rule_group.update(rule_group_params)
      redirect_to rules_path, notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule_group.destroy!
    redirect_to rules_path, notice: t(".success")
  end

  private
    def set_rule_group
      @rule_group = Current.family.rule_groups.find(params[:id])
    end

    def rule_group_params
      params.require(:rule_group).permit(:name)
    end
end
