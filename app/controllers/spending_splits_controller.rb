# Fulas Bank: from the Resumen, the 50/30/20 target and which categories are
# necessary, discretionary or saving (see Category::SpendingSplit).
class SpendingSplitsController < ApplicationController
  def edit
    @target = Category::SpendingSplit.target_for(Current.user)
    @categories = Current.family.categories.roots.reject(&:analytics_neutral?).sort_by(&:display_sort_key)
    @subcategories = Current.family.categories.where(parent_id: @categories.map(&:id)).sort_by(&:display_sort_key).group_by(&:parent_id)
  end

  def update
    target = Array(params[:target]).first(3).map(&:to_i)
    if target.size == 3 && target.sum == 100 && target.all? { |value| value >= 0 }
      Current.user.update_dashboard_preferences(Category::SpendingSplit::TARGET_PREFERENCE => target)
    else
      return redirect_back_or_to category_summaries_path, alert: t(".invalid_target")
    end

    categories = Current.family.categories.to_a
    classes = params.fetch(:classes, {}).permit(*categories.map(&:id)).to_h
    categories.select { |category| classes.key?(category.id) }.each do |category|
      value = classes[category.id].presence
      category.update!(spending_class: value) if value.nil? || Category::SpendingClass::CLASSES.include?(value)
    end

    redirect_back_or_to category_summaries_path, notice: t(".success")
  end
end
