# GitHub Codespaces (see .devcontainer/probar and bin/probar) serves the app
# from https://<codespace>-3000.app.github.dev through a proxy, so the
# browser's Origin header never matches the URL Rails sees. Only applies when
# running inside a Codespace, in development or in the trial production mode.
if ENV["CODESPACES"] == "true" || ENV["FULAS_CODESPACE"] == "true"
  Rails.application.configure do
    config.action_controller.forgery_protection_origin_check = false
    config.action_cable.disable_request_forgery_protection = true
  end
end
