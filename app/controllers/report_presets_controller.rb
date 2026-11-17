# Fulas Bank: saving the «Informe»'s current choices with a name, and
# deleting a saved one (see ReportPreset).
class ReportPresetsController < ApplicationController
  def create
    preset = Current.user.report_presets.find_or_initialize_by(name: params.dig(:report_preset, :name).to_s.strip)
    allowed = accessible_accounts.visible.pluck(:id).map(&:to_s)
    preset.assign_attributes(
      account_ids: Array(params.dig(:report_preset, :account_ids)).map(&:to_s) & allowed,
      sections: Array(params.dig(:report_preset, :sections)).map(&:to_s) & StatusReport::SECTIONS,
      period: params.dig(:report_preset, :period).to_s
    )

    if preset.save
      redirect_to status_report_path(preset_id: preset.id), notice: t(".success", name: preset.name)
    else
      redirect_back_or_to status_report_path, alert: preset.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.user.report_presets.find(params[:id]).destroy!
    redirect_to status_report_path, notice: t(".success")
  end
end
