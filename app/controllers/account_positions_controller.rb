# Fulas Bank: "Ordenar cuentas", the accounts panel's order set by hand.
# Each account moves up or down within its group (Cuentas, Tarjetas...); the
# order is saved in the user's preferences (User#account_positions) and
# becomes the one used ("manual").
class AccountPositionsController < ApplicationController
  def edit
    @groups = ordered_groups
  end

  def update
    groups = ordered_groups
    group = groups.find { |each| each.accounts.any? { |account| account.id.to_s == params[:account_id].to_s } }
    raise ActiveRecord::RecordNotFound unless group

    ids = group.accounts.map { |account| account.id.to_s }
    index = ids.index(params[:account_id].to_s)
    target = params[:direction] == "up" ? index - 1 : index + 1
    ids[index], ids[target] = ids[target], ids[index] if target.between?(0, ids.size - 1)

    order = groups.flat_map { |each| each == group ? ids : each.accounts.map { |account| account.id.to_s } }
    Current.user.save_account_positions!(order)

    @groups = ordered_groups(reload: true)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("account-positions", partial: "account_positions/list", locals: { groups: @groups }) }
      format.html { redirect_to edit_account_positions_path }
    end
  end

  # Back to the order by name.
  def destroy
    Current.user.update!(default_account_order: "name_asc")
    redirect_back_or_to root_path, notice: t(".success")
  end

  private
    # The panel's groups, assets then liabilities, in the order shown now.
    def ordered_groups(reload: false)
      sheet = reload ? BalanceSheet.new(Current.family, user: Current.user.reload) : Current.family.balance_sheet(user: Current.user)
      sheet.assets.account_groups + sheet.liabilities.account_groups
    end
end
