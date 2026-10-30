# Fulas Bank: what to do with a row that looks like a movement entered by
# hand (TransactionImport#possible_duplicates): the same movement keeping its
# name, the same one taking the file's name, or a different one.
class Import::DuplicatesController < ApplicationController
  before_action :set_import

  def update
    row = @import.rows.find(params[:row_id])
    choice = params[:choice].to_s
    row.update_column(:duplicate_choice, choice) if TransactionImport::CHOICES.include?(choice)

    redirect_to import_path(@import, anchor: "possible-duplicates")
  end

  private
    def set_import
      @import = Current.family.imports.find(params[:import_id])
    end
end
