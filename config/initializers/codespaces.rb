# GitHub Codespaces (see .devcontainer/probar and bin/probar) serves the app
# from https://<codespace>-3000.app.github.dev through a proxy, so the
# browser's Origin header need not match the URL Rails sees. Only applies when
# running inside a Codespace, in development or in the trial production mode.
#
# Set on the controller class itself: by the time config/initializers run in
# production, the action_controller config has already been copied over.
if ENV["CODESPACES"] == "true" || ENV["FULAS_CODESPACE"] == "true"
  ActiveSupport.on_load(:action_controller_base) do
    self.forgery_protection_origin_check = false
  end

  Rails.application.config.action_cable.disable_request_forgery_protection = true
end
