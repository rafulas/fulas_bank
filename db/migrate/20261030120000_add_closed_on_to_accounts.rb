# Fulas Bank: the day an account was closed or stopped being used (an old
# bank, a motorbike sold, a loan paid off). It keeps its history and its
# place in the net worth of those days, but goes to the end of the account
# lists when a new movement is entered.
class AddClosedOnToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :closed_on, :date
  end
end
