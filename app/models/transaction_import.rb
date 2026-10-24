class TransactionImport < Import
  def import!
    transaction do
      mappings.each(&:create_mappable!)

      new_transactions = []
      updated_entries = []
      skipped_transfers = 0
      claimed_entry_ids = Set.new # Track entries we've already claimed in this import

      rows.each_with_index do |row, index|
        mapped_account = if account
          account
        else
          mappings.accounts.mappable_for(row.account)
        end

        # Guard against nil account - this happens when an account name in CSV is not mapped
        if mapped_account.nil?
          row_number = index + 1
          account_name = row.account.presence || "(blank)"
          error_message = "Row #{row_number}: Account '#{account_name}' is not mapped to an existing account. " \
                         "Please map this account in the import configuration."
          errors.add(:base, error_message)
          raise Import::MappingError, error_message
        end

        category = mappings.categories.mappable_for(row.category)
        tags = row.tags_list.map { |tag| mappings.tags.mappable_for(tag) }.compact
        merchant = merchant_for(row.merchant)

        # Use account's currency when no currency column was mapped in CSV, with family currency as fallback
        effective_currency = currency_col_label.present? ? row.currency : (mapped_account.currency.presence || family.currency)

        # Check for duplicate transactions using the adapter's deduplication logic
        # Pass claimed_entry_ids to exclude entries we've already matched in this import
        # This ensures identical rows within the CSV are all imported as separate transactions
        adapter = Account::ProviderImportAdapter.new(mapped_account)
        duplicate_entry = adapter.find_duplicate_transaction(
          date: row.date_iso,
          amount: row.signed_amount,
          currency: effective_currency,
          name: row.name,
          exclude_entry_ids: claimed_entry_ids
        )

        # Fulas Bank: the same transfer often comes from two files with two
        # names (the bank's «Traspaso programa Tu Cuenta», Bilance's «Redondeo
        # tarjeta»). It is a transfer in both, so it is kept once.
        if duplicate_entry.nil? && category&.special_transfers?
          transfer_duplicate = transfer_duplicate_for(mapped_account, row, effective_currency, claimed_entry_ids)
          if transfer_duplicate
            claimed_entry_ids.add(transfer_duplicate.id)
            skipped_transfers += 1
            next
          end
        end

        if duplicate_entry
          # Update existing transaction instead of creating a new one.
          # Fulas Bank: only what it lacks, so importing the same statement
          # again never undoes a category, shop, tags or notes set by hand.
          existing = duplicate_entry.transaction
          existing.category = category if category.present? && existing.category_id.nil?
          existing.tags = tags if tags.any? && existing.tags.empty?
          existing.merchant = merchant if merchant.present? && existing.merchant_id.nil?
          duplicate_entry.notes = row.notes if row.notes.present? && duplicate_entry.notes.blank?
          duplicate_entry.import = self
          duplicate_entry.import_locked = true  # Protect from provider sync overwrites
          updated_entries << duplicate_entry
          claimed_entry_ids.add(duplicate_entry.id)
        else
          # Create new transaction (no duplicate found)
          # Mark as import_locked to protect from provider sync overwrites
          new_transactions << Transaction.new(
            category: category,
            tags: tags,
            merchant: merchant,
            entry: Entry.new(
              account: mapped_account,
              date: row.date_iso,
              amount: row.signed_amount,
              name: row.name,
              currency: effective_currency,
              notes: row.notes,
              import: self,
              import_locked: true
            )
          )
        end
      end

      # Save updated entries first
      updated_entries.each do |entry|
        entry.transaction.save!
        entry.save!
      end

      # Bulk import new transactions
      Transaction.import!(new_transactions, recursive: true) if new_transactions.any?

      # Fulas Bank: what the file brought, for the final screen.
      update_column(:summary, (summary || {}).merge(
        SUMMARY_KEY => { "created" => new_transactions.size, "existing" => updated_entries.size + skipped_transfers }
      ))
    end
  end

  SUMMARY_KEY = "transactions".freeze

  # Fulas Bank: { "created" => n, "existing" => m } once published, or nil.
  def published_counts
    counts = (summary || {})[SUMMARY_KEY]
    counts if counts.is_a?(Hash) && counts.key?("existing")
  end

  # Fulas Bank: on the confirm step, the transactions that will be added,
  # not counting the rows already in the account (re-importing a statement
  # that overlaps the last one), which are not added again.
  def dry_run
    super.merge(transactions: [ rows_count - existing_rows_count, 0 ].max)
  end

  # Rows that match a movement already in their account, by the same rule as
  # the import (same day, amount, currency and name, each movement once).
  # One query per account rather than one per row.
  def existing_rows_count
    @existing_rows_count ||= rows.group_by { |row| account || mappings.accounts.mappable_for(row.account) }.sum do |mapped_account, account_rows|
      next 0 if mapped_account.nil?

      dates = account_rows.filter_map { |row| row_date(row) }
      next 0 if dates.empty?

      available = mapped_account.entries.where(entryable_type: "Transaction", external_id: nil, date: dates.min..dates.max)
                                .pluck(:date, :amount, :currency, :name)
                                .map { |date, amount, currency, name| [ date.iso8601, amount.to_d, currency, name ] }
                                .tally
      account_rows.count do |row|
        currency = currency_col_label.present? ? row.currency : (mapped_account.currency.presence || family.currency)
        key = [ row_date(row), row.signed_amount, currency, row.name ]
        next false unless available[key].to_i.positive?

        available[key] -= 1
        true
      end
    end
  end

  def required_column_keys
    %i[date amount]
  end

  def column_keys
    base = %i[date amount name merchant currency category tags notes]
    base.unshift(:account) if account.nil?
    base
  end

  def mapping_steps
    base = [ Import::CategoryMapping, Import::TagMapping ]
    base << Import::AccountMapping if account.nil?
    base
  end

  def selectable_amount_type_values
    return [] if entity_type_col_label.nil?

    csv_rows.map { |row| row[entity_type_col_label] }.uniq
  end

  # A row's date as ISO text, or nil when it cannot be read yet.
  def row_date(row)
    row.date_iso
  rescue ArgumentError, TypeError
    nil
  end

  # Fulas Bank: the family's merchant with that name, created when there is
  # none yet. Names match ignoring case and surrounding spaces, so «LIDL» and
  # «Lidl» are one merchant. Remembered per import, so each name is looked up
  # once however many rows carry it.
  def merchant_for(name)
    name = name.to_s.squish
    return if name.blank?

    @merchants_by_name ||= {}
    @merchants_by_name[name.downcase] ||=
      family.merchants.where("LOWER(name) = ?", name.downcase).first ||
      family.merchants.create!(name: name)
  end

  # Fulas Bank: an entry already in the account, same day, amount and
  # currency, that is a transfer too: matched as one, or in «Traspasos».
  # Any name, as the bank and Bilance word the same transfer differently.
  def transfer_duplicate_for(account, row, currency, claimed_entry_ids)
    candidates = account.entries
                        .where(entryable_type: "Transaction", date: row.date_iso, amount: row.signed_amount, currency: currency)
                        .where.not(id: claimed_entry_ids.to_a)
                        .includes(entryable: :category)
                        .order(:created_at)

    candidates.find do |entry|
      transaction = entry.entryable
      transaction.transfer? || transaction.transfer.present? || transaction.category&.special_transfers?
    end
  end

  def csv_template
    template = <<~CSV
      date*,amount*,name,currency,category,tags,account,notes
      2024-05-15,-45.99,Grocery Store,USD,Food,groceries|essentials,Checking Account,Monthly grocery run
      2024-05-16,1500.00,Salary,,Income,,Main Account,
      2024-05-17,-12.50,Coffee Shop,,,coffee,,
    CSV

    csv = CSV.parse(template, headers: true)
    csv.delete("account") if account.present?
    csv
  end
end
