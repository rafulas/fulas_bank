# Fulas Bank: every day, the policies that will not be renewed and whose end
# has come are marked as no longer in force (see Insurance#ends_on).
class ExpireInsurancesJob < ApplicationJob
  queue_as :scheduled

  def perform
    Insurance.expire_ended!
  end
end
