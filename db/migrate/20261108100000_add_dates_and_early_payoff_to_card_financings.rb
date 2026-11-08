# Fulas Bank: a financed card purchase can be given the day of its fee and of
# its first instalment, when the bank does not follow the card's charge day,
# and be paid off early (the day and what was paid). See CardFinancing.
class AddDatesAndEarlyPayoffToCardFinancings < ActiveRecord::Migration[8.1]
  def change
    add_column :card_financings, :fee_on, :date
    add_column :card_financings, :first_installment_on, :date
    add_column :card_financings, :paid_off_on, :date
    add_column :card_financings, :payoff_amount, :decimal, precision: 19, scale: 4
  end
end
