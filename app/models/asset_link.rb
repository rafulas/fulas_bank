# Lookups across the records that link a bank charge to a vehicle or a
# property (see BankChargeLinkable).
module AssetLink
  module_function

  def models
    BankChargeLinkable.linkable_models
  end

  # Ids of the charges already linked to some record, leaving out `except`
  # (the record being edited, whose own charge is still available to it).
  def linked_entry_ids(except: nil)
    models.flat_map do |model|
      scope = model.where.not(entry_id: nil)
      scope = scope.where.not(id: except.id) if except.is_a?(model) && except.persisted?
      scope.pluck(:entry_id)
    end
  end

  # The record a charge is linked to, if any.
  def for_entry(entry)
    return if entry.blank?

    models.each do |model|
      record = model.find_by(entry_id: entry.id)
      return record if record
    end

    nil
  end

  # Records the app proposed for an account and the user has not answered.
  def suggestions_for(account)
    case account.accountable_type
    when "Vehicle" then account.vehicle.logs.suggested
    when "Property" then account.property.expenses.suggested
    else Vehicle::Log.none
    end
  end
end
