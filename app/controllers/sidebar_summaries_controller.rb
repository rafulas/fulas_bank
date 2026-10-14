# Fulas Bank: the summary at the top of the left panel (net worth, assets,
# debts and the chosen accounts' total). It loads in its own frame after the
# page, so the page itself stays as quick as before and a refresh of the
# page does not wait for it.
class SidebarSummariesController < ApplicationController
  def show
    render partial: "accounts/sidebar_summary", locals: { family: Current.family, user: Current.user }, layout: false
  end
end
