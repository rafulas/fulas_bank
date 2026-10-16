# Fulas Bank: a subscription is only what can be cancelled at will. The
# detector used to take a flat, small card charge with no English keyword
# for one, so Spanish insurance, the mortgage or the phone bill could end up
# among the subscriptions. This moves those to "bill" or "installment" (see
# RecurringTransaction::Classifier.refile_obligations!). Nothing else on
# them changes.
class RefileObligatorySubscriptions < ActiveRecord::Migration[8.1]
  def up
    RecurringTransaction.reset_column_information

    Family.find_each do |family|
      RecurringTransaction::Classifier.refile_obligations!(family)
    end
  end

  def down
    # Which ones were moved is not recorded; they stay where they are.
  end
end
