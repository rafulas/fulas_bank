# Fulas Bank: a loan's first instalment can fall on a date of its own (not
# always a month after it was taken out), and a loan repaid early keeps the
# day it was. See Loan#first_payment_date and Loan#paid_off_on.
class AddFirstPaymentDateAndPaidOffOnToLoans < ActiveRecord::Migration[8.1]
  def change
    add_column :loans, :first_payment_date, :date
    add_column :loans, :paid_off_on, :date
  end
end
