# Labels and paths shared by vehicle logs and property expenses, for the
# screens that show both kinds of record: the suggestions box and the bank
# movement's detail.
module AssetLinksHelper
  def asset_record_title(record)
    case record
    when Vehicle::Log then vehicle_log_title(record)
    when Property::Expense then property_expense_kind_label(record.kind)
    end
  end

  def asset_record_icon(record)
    case record
    when Vehicle::Log then vehicle_log_icon(record)
    when Property::Expense then property_expense_icon(record.kind)
    end
  end

  def asset_record_edit_path(record)
    case record
    when Vehicle::Log then edit_vehicle_log_path(record.asset_account, record)
    when Property::Expense then edit_property_expense_path(record.asset_account, record)
    end
  end

  # The form to link a bank movement to a vehicle or a property, with the
  # charge chosen and the kind its category points to (a "Combustible"
  # charge opens a refuel).
  def asset_link_new_path(account, entry)
    rule = AssetLinker.new(account.family).target_for_account(entry, account)

    if account.vehicle?
      new_vehicle_log_path(account, entry_id: entry.id, kind: rule.kind, category: rule.category)
    else
      new_property_expense_path(account, entry_id: entry.id, kind: rule.kind)
    end
  end

  # The vehicles and properties a bank movement can be linked to: only
  # outgoing payments (a loan payment can be the mortgage), never a split
  # parent or a transfer between the user's own accounts.
  def asset_link_accounts_for(entry)
    transaction = entry.transaction
    return [] unless entry.amount.positive? && !entry.split_parent?
    return [] if transaction.transfer? && !transaction.loan_payment?

    accounts = accessible_accounts.visible.where(accountable_type: %w[Vehicle Property]).alphabetically.to_a
    accounts.reject!(&:vehicle?) if transaction.loan_payment?
    accounts
  end

  def property_expense_kind_label(kind)
    t("properties.expenses.kinds.#{kind}")
  end

  def property_expense_kind_options
    Property::Expense::KINDS.map { |kind| [ property_expense_kind_label(kind), kind ] }
  end

  def property_expense_icon(kind)
    {
      "mortgage" => "landmark",
      "insurance" => "umbrella",
      "renovation" => "hammer",
      "maintenance" => "wrench",
      "community" => "building",
      "tax" => "receipt-text",
      "utilities" => "lightbulb",
      "furniture" => "bed-single"
    }.fetch(kind, "home")
  end

  # The bank charges an expense can be linked to: date, description, amount
  # and account. The charge already linked stays in the list.
  def property_expense_entry_options(expense)
    entries = expense.candidate_entries(scope: Current.accessible_entries)
    entries = [ expense.entry, *entries.reject { |entry| entry.id == expense.entry_id } ] if expense.entry.present?

    entries.map do |entry|
      label = [ format_date(entry.date), entry.name, format_money(entry.amount_money), entry.account.name ].join(" · ")
      [ label, entry.id ]
    end
  end
end
