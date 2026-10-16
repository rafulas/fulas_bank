# Fulas Bank: a premium paid in instalments the user sets (payment_frequency
# "custom"): for example three payments of 150 € every 45 days from the day
# the policy starts. Each instalment is { "date" => "2026-09-01",
# "amount" => "150.0" }; the dates repeat every year of the policy.
class AddInstallmentsToInsurances < ActiveRecord::Migration[8.1]
  def change
    add_column :insurances, :installments, :jsonb, default: [], null: false
  end
end
