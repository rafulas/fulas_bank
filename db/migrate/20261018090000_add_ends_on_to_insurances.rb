# Fulas Bank: a policy that will not be renewed ends on this day (its next
# renewal when the user said so). From then on it is no longer in force:
# ExpireInsurancesJob marks it inactive, and the Forecast stops expecting it.
class AddEndsOnToInsurances < ActiveRecord::Migration[8.1]
  def change
    add_column :insurances, :ends_on, :date
  end
end
