# Fulas Bank: the «Necesita revisión» bell in the top bar (see ReviewItems).
# The bell loads in its own frame so working out the items never slows the
# page it sits on.
class ReviewItemsController < ApplicationController
  KEY_FORMAT = /\A(duplicate|price|overdue|due):[0-9a-f:-]{36,73}\z/

  def index
    @review = ReviewItems.new(Current.family, user: Current.user)
    render layout: false
  end

  def seen
    key = params[:key].to_s
    ReviewItems.mark_seen!(Current.user, key) if key.match?(KEY_FORMAT)

    redirect_back_or_to root_path
  end
end
