# Proposes links between the family's bank charges and its vehicles and
# properties, so the user only has to confirm them (like the transfers the app
# pairs on its own).
#
# For each outgoing charge that is not linked yet, it works out which asset it
# belongs to and what it is, in this order:
#   1. A loan payment to a loan tied to a property: that property's mortgage.
#   2. A tag on the charge naming the asset: its account name, the vehicle's
#      plate or model, or a plain word such as "coche" or "casa" when the
#      family has only one asset of that kind. The category then says what it
#      is; without a known category it is an "other" cost.
#   3. Otherwise its category (Combustible → refuel, Seguro de hogar → home
#      insurance...), when the family has a single asset of that kind.
#
# Then it looks in that asset for a record of the same kind within a few days
# that has no charge yet (a refuel typed by hand or imported from RoadTrip)
# and proposes linking them ("link"). Amounts are not compared: what was paid
# often differs from the fuel put in (discounts, a coffee...). If there is no
# such record, it creates one from the charge ("new"), for the user to
# complete (km, litres) and confirm.
#
# Charges the user rejected for an account are never proposed again for it.
class AssetLinker
  # Automatic runs (after an import or a sync) only look this far back; the
  # "Search the bank" button looks at the whole history.
  AUTO_LOOKBACK = 12.months

  # A record and a charge this many days apart can be the same purchase (the
  # bank often books a card payment a day or two later).
  SAME_CHARGE_DAYS = 3

  Rule = Data.define(:kind, :category, :needs_tag)

  # Category names (as in Category::FulasTree, compared without accents or
  # case) and what a charge in them is for a vehicle. `needs_tag` marks
  # categories that are not only about the car, so they need the tag too.
  VEHICLE_RULES = {
    "combustible" => Rule.new(kind: "fuel", category: nil, needs_tag: false),
    "vehiculo y mantenimiento" => Rule.new(kind: "service", category: nil, needs_tag: false),
    "seguro del vehiculo" => Rule.new(kind: "expense", category: "insurance", needs_tag: false),
    "peajes" => Rule.new(kind: "expense", category: "toll", needs_tag: false),
    "aparcamiento" => Rule.new(kind: "expense", category: "parking", needs_tag: false),
    "accesorios vehiculos" => Rule.new(kind: "expense", category: "accessories", needs_tag: false),
    "leasing" => Rule.new(kind: "expense", category: "other", needs_tag: false),
    "multas" => Rule.new(kind: "expense", category: "fine", needs_tag: true),
    "impuestos" => Rule.new(kind: "expense", category: "road_tax", needs_tag: true),
    "seguros" => Rule.new(kind: "expense", category: "insurance", needs_tag: true)
  }.freeze

  PROPERTY_RULES = {
    "alquiler e hipoteca" => Rule.new(kind: "mortgage", category: nil, needs_tag: false),
    "seguro de hogar" => Rule.new(kind: "insurance", category: nil, needs_tag: false),
    "reformas y construccion" => Rule.new(kind: "renovation", category: nil, needs_tag: false),
    "mantenimiento y reparaciones" => Rule.new(kind: "maintenance", category: nil, needs_tag: false),
    "comunidad" => Rule.new(kind: "community", category: nil, needs_tag: false),
    "energia y suministros" => Rule.new(kind: "utilities", category: nil, needs_tag: false),
    "muebles y decoracion" => Rule.new(kind: "furniture", category: nil, needs_tag: false),
    "impuestos" => Rule.new(kind: "tax", category: nil, needs_tag: true),
    "seguros" => Rule.new(kind: "insurance", category: nil, needs_tag: true),
    "prestamos e intereses" => Rule.new(kind: "mortgage", category: nil, needs_tag: true)
  }.freeze

  VEHICLE_FALLBACK = Rule.new(kind: "expense", category: "other", needs_tag: true)
  PROPERTY_FALLBACK = Rule.new(kind: "other", category: nil, needs_tag: true)
  MORTGAGE = PROPERTY_RULES.fetch("alquiler e hipoteca")

  # Tags that name "the" car or "the" home when the family has only one.
  VEHICLE_WORDS = %w[coche vehiculo auto moto car].freeze
  PROPERTY_WORDS = %w[casa vivienda hogar piso home].freeze

  # Run after imports, syncs and rules: a failure here must never break them.
  def self.run_quietly(family)
    new(family).run!
  rescue => error
    Rails.logger.error("AssetLinker failed for family #{family.id}: #{error.message}")
    Sentry.capture_exception(error) if defined?(Sentry)
    0
  end

  def self.normalize(text)
    ActiveSupport::Inflector.transliterate(text.to_s).downcase.squish
  end

  attr_reader :family, :since

  # `since: nil` looks at every charge the family has.
  def initialize(family, since: AUTO_LOOKBACK.ago.to_date)
    @family = family
    @since = since
  end

  # Returns how many links it proposed.
  def run!
    return 0 if assets.empty?

    adopt_pending_suggestions

    charges.sum do |entry|
      target = target_for(entry)
      next 0 if target.nil?

      account, rule = target
      next 0 if rejected?(entry, account)

      propose!(account, rule, entry)
      1
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      Rails.logger.warn("AssetLinker skipped entry #{entry.id}: #{error.message}")
      0
    end
  end

  # [ account, rule ] for a charge, or nil when it does not clearly belong to
  # one of the family's vehicles or properties.
  def target_for(entry)
    transaction = entry.entryable
    return mortgage_target(transaction) if transaction.loan_payment?
    return if transaction.transfer? || transaction.transfer.present?

    tagged = tagged_assets(transaction)
    return if tagged.size > 1

    if tagged.one?
      account = tagged.first
      return [ account, rule_for(account, transaction) ]
    end

    category_target(transaction)
  end

  # What a charge would be for a given asset, when the user links it by hand:
  # the kind its category points to, or "other".
  def target_for_account(entry, account)
    transaction = entry.entryable
    return MORTGAGE if account.property? && transaction.loan_payment?

    rule_for(account, transaction)
  end

  private
    def assets
      @assets ||= family.accounts.visible
                        .where(accountable_type: %w[Vehicle Property])
                        .includes(:accountable)
                        .to_a
    end

    def vehicles
      @vehicles ||= assets.select(&:vehicle?)
    end

    def properties
      @properties ||= assets.select(&:property?)
    end

    def charges
      scope = family.entries
                    .where(entryable_type: "Transaction", excluded: false)
                    .where("entries.amount > 0")
                    .where.not(id: AssetLink.linked_entry_ids)
                    .where.not(account_id: assets.map(&:id))
      scope = scope.where(date: since..) if since
      scope.preload(:account, entryable: [ :tags, { category: :parent } ]).order(:date).to_a
    end

    def rejected?(entry, account)
      @rejections ||= AssetLinkRejection.where(account_id: assets.map(&:id)).pluck(:entry_id, :account_id).to_set
      @rejections.include?([ entry.id, account.id ])
    end

    # A payment to a loan the user tied to a property (the loan's "asset").
    def mortgage_target(transaction)
      loan_account = transaction.transfer&.to_account
      return unless loan_account&.loan?

      property = properties.find { |account| account.id == loan_account.loan.asset_account_id }
      [ property, MORTGAGE ] if property
    end

    def category_target(transaction)
      vehicle_rule = category_rule(VEHICLE_RULES, transaction)
      return [ vehicles.first, vehicle_rule ] if vehicle_rule && !vehicle_rule.needs_tag && vehicles.one?

      property_rule = category_rule(PROPERTY_RULES, transaction)
      [ properties.first, property_rule ] if property_rule && !property_rule.needs_tag && properties.one?
    end

    def rule_for(account, transaction)
      rules, fallback = account.vehicle? ? [ VEHICLE_RULES, VEHICLE_FALLBACK ] : [ PROPERTY_RULES, PROPERTY_FALLBACK ]
      category_rule(rules, transaction) || fallback
    end

    # The rule for the charge's category, or for its parent category (a
    # subcategory the user added under "Combustible" still counts as fuel).
    def category_rule(rules, transaction)
      category = transaction.category
      return if category.nil?

      rules[self.class.normalize(category.name)] || (category.parent && rules[self.class.normalize(category.parent.name)])
    end

    def tagged_assets(transaction)
      tags = transaction.tags.map { |tag| self.class.normalize(tag.name) }
      return [] if tags.empty?

      assets.select { |account| (names_for(account) & tags).any? }
    end

    def names_for(account)
      @names ||= {}
      @names[account.id] ||= begin
        names = [ account.name ]

        if account.vehicle?
          vehicle = account.vehicle
          names += [ vehicle.license_plate, vehicle.model, [ vehicle.make, vehicle.model ].compact.join(" ") ]
          names += VEHICLE_WORDS if vehicles.one?
        else
          names += PROPERTY_WORDS if properties.one?
        end

        names.map { |name| self.class.normalize(name) }.reject(&:blank?).uniq
      end
    end

    def records_for(account)
      account.vehicle? ? account.vehicle.logs : account.property.expenses
    end

    # An existing record of the same kind, a few days from the charge and not
    # linked to any: the closest in date, then in amount.
    def existing_match(account, kind, entry)
      records_for(account)
        .where(entry_id: nil, suggestion: nil, kind: kind)
        .where(date: (entry.date - SAME_CHARGE_DAYS)..(entry.date + SAME_CHARGE_DAYS))
        .to_a
        .min_by { |record| [ (record.date - entry.date).abs, (record.amount.to_d - entry.amount.abs).abs ] }
    end

    def propose!(account, rule, entry)
      if (record = existing_match(account, rule.kind, entry))
        record.update!(entry: entry, suggestion: "link")
      else
        build_record(account, rule, entry).save!
      end
    end

    def build_record(account, rule, entry)
      attributes = {
        date: entry.date,
        amount: entry.amount.abs,
        currency: account.currency,
        entry: entry,
        suggestion: "new"
      }

      if account.vehicle?
        account.vehicle.logs.new(
          attributes.merge(
            kind: rule.kind,
            category: (rule.category || "other" if rule.kind == "expense"),
            notes: (entry.name unless rule.kind == "fuel")
          )
        )
      else
        account.property.expenses.new(attributes.merge(kind: rule.kind, notes: entry.name))
      end
    end

    # A record the app created from a charge before the user typed the real
    # one (by hand or from RoadTrip): the charge moves to the user's record and
    # the app's copy goes. Copies whose charge was deleted go too.
    def adopt_pending_suggestions
      assets.each do |account|
        records_for(account).pending.includes(:entry).find_each do |pending|
          if pending.entry.nil?
            pending.destroy!
            next
          end

          match = existing_match(account, pending.kind, pending.entry)
          next if match.nil?

          entry = pending.entry
          pending.class.transaction do
            pending.destroy!
            match.update!(entry: entry, suggestion: "link")
          end
        end
      end
    end
end
