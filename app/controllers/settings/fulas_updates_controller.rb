# Fulas Bank: «Actualizar ahora» (and «Volver a la versión anterior») from
# Ajustes › Autoalojamiento. Only leaves the request; the server does the
# work (FulasUpdate).
class Settings::FulasUpdatesController < ApplicationController
  guard_feature unless: -> { self_hosted? }
  before_action :ensure_admin

  def create
    requested = FulasUpdate::ACTIONS.find { |name| name == params[:accion].to_s }
    if requested && FulasUpdate.new.request!(requested)
      redirect_to settings_hosting_path(anchor: "fulas-update"), notice: t(".requested_#{requested}")
    else
      redirect_to settings_hosting_path(anchor: "fulas-update"), alert: t(".not_requested")
    end
  end

  private
    def ensure_admin
      redirect_to settings_hosting_path, alert: t("settings.hostings.not_authorized") unless Current.user.admin?
    end
end
