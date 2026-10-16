# Fulas Bank: the account the instalments of an insurance are charged to, so
# the Forecast can expect them there (by default, the Forecast's main
# account). Deleting the account keeps the policy, without it.
class AddPaymentAccountToInsurances < ActiveRecord::Migration[8.1]
  def change
    add_reference :insurances, :payment_account, type: :uuid,
                  foreign_key: { to_table: :accounts, on_delete: :nullify }
  end
end
