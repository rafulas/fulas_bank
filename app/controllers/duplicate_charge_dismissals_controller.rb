# Fulas Bank: the user says a possible double charge on Inicio is fine; it is
# not shown again (see DuplicateCharges).
class DuplicateChargeDismissalsController < ApplicationController
  KEY_FORMAT = /\A[0-9a-f-]{36}:[0-9a-f-]{36}\z/

  def create
    key = params[:key].to_s
    DuplicateCharges.dismiss!(Current.user, key) if key.match?(KEY_FORMAT)

    redirect_back_or_to root_path, notice: t(".dismissed")
  end
end
