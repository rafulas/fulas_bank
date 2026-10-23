# Fulas Bank: recurring movements are now fixed, a bill or a subscription
# (see RecurringTransaction::Kind). This files each series under the kind
# its name and category say (the mortgage and loans fixed; power, phone and
# insurance bills; Netflix or the gym subscriptions), for the user to
# review; and a movement marked "recurrente" (a fixed one that ends) is now
# simply fixed, its end kept on its series.
class ReclassifyRecurringIntoThreeKinds < ActiveRecord::Migration[8.1]
  def up
    RecurringTransaction.reset_column_information

    execute "UPDATE transactions SET expense_type = 'fixed' WHERE expense_type = 'recurring'"

    Family.find_each do |family|
      RecurringTransaction::Kind.reclassify!(family)
    end
  end

  def down
    # Which ones were moved is not recorded; they stay where they are.
  end
end
