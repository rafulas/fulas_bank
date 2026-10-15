# Fulas Bank's example family, for the trial copies (bin/probar, in a
# Codespace or in VS Code): a Spanish household in euros that uses what Fulas
# Bank adds to Sure, so every screen has something to show.
#
#   - Accounts: a current account, a savings account, a credit card, an index
#     fund, a broker with IBEX shares, a flat with its mortgage and a car.
#   - About a year of movements in Fulas Bank's own categories (salaries,
#     bills, supermarket, fuel, holidays...), the card paid each month from the
#     current account, and monthly transfers to savings and to the fund.
#   - The car's logbook (refuels, workshop, insurance, road tax, ITV) and the
#     flat's expenses (mortgage, community, insurance, IBI, a renovation),
#     linked to their bank charges. The latest few are left for the app to
#     propose, so «Cargos del banco por revisar» has something to show.
#   - Recurring payments found by the app itself, budgets for the last months,
#     and two one-off items in the Forecast.
#
# `generate!` replaces any family whose user has the example email, and
# leaves every other family alone: a trial copy may also hold your own data.
# Sure's American example family (Demo::Generator) stays as it was, as the
# job behind Settings' «load sample data» still uses it.
class Demo::FulasGenerator
  SAFE_ENVIRONMENTS = %w[development test].freeze
  PASSWORD = "Password1!".freeze

  def initialize(seed: 42)
    @rng = Random.new(seed.to_i)
    @today = Date.current
    @start = (@today << 12).beginning_of_month
  end

  def generate!(email: Rails.application.config_for(:demo).fetch(:email))
    unless SAFE_ENVIRONMENTS.include?(Rails.env)
      raise SecurityError, "Demo::FulasGenerator only runs in #{SAFE_ENVIRONMENTS.join(', ')}"
    end

    remove_previous_family!(email)

    ActiveRecord::Base.transaction do
      @family = create_family!(email)
      create_accounts!
      create_movements!
      # Before syncing: a sync also runs AssetLinker, which would otherwise
      # take these charges for its own proposals first.
      car_logbook!
      flat_records!
      create_budgets!
      create_forecast_items!
    end

    finish!
    @family
  end

  private
    attr_reader :family, :today, :start

    # ---------------------------------------------------------------- family

    # The previous example family (Sure's or an older Fulas one), found by its
    # users' emails. Its fake subscription and monitoring key would stop the
    # family from being destroyed, as in Demo::DataCleaner.
    def remove_previous_family!(email)
      users = User.where(email: [ email, "partner_#{email}" ])
      Family.where(id: users.select(:family_id)).find_each do |old|
        old_user_ids = old.users.pluck(:id)
        ApiKey.where(user_id: old_user_ids, display_key: ApiKey::DEMO_MONITORING_KEY).delete_all
        Subscription.where(family_id: old.id).update_all(status: "canceled")
        old.destroy!
      end
    end

    def create_family!(email)
      new_family = Family.create!(
        name: "Familia García",
        currency: "EUR",
        locale: "es",
        country: "ES",
        timezone: "Europe/Madrid",
        date_format: "%d/%m/%Y",
        # Fulas Bank's categories and subcategories (Category::FulasTree).
        with_default_categories: true
      )

      new_family.users.create!(email: email, first_name: "Lucía", last_name: "García", role: "admin",
                               password: PASSWORD, onboarded_at: Time.current)
      new_family.users.create!(email: "partner_#{email}", first_name: "Javier", last_name: "Martín", role: "member",
                               password: PASSWORD, onboarded_at: Time.current)
      new_family
    end

    # -------------------------------------------------------------- accounts

    def create_accounts!
      @current = account!(Depository.new(subtype: "checking"), "Cuenta nómina")
      @savings = account!(Depository.new(subtype: "savings"), "Cuenta ahorro")
      @card = account!(CreditCard.new, "Tarjeta de crédito")
      @fund = account!(Investment.new, "Fondo indexado")
      @broker = account!(Investment.new, "Bróker acciones")

      @flat = account!(Property.new(subtype: "apartment", area_value: 92, area_unit: "sqm", year_built: 2004), "Piso")
      @car = account!(
        Vehicle.new(make: "Seat", model: "León", year: 2020, fuel_type: "gasoline", license_plate: "1234 LMN",
                    mileage_unit: "km", purchase_date: (today << 66).change(day: 14), purchase_price: 21_900),
        "Seat León"
      )

      mortgage_start = (today << 74).beginning_of_month
      @mortgage = account!(
        Loan.new(subtype: "mortgage", rate_type: "fixed", interest_rate: 2.1, term_months: 300,
                 start_date: mortgage_start, initial_balance: 180_000, down_payment: 45_000,
                 asset_account_id: @flat.id),
        "Hipoteca piso"
      )

      opening_balances!(mortgage_start)
    end

    def account!(accountable, name)
      family.accounts.create!(accountable: accountable, name: name, balance: 0, currency: "EUR")
    end

    def opening_balances!(mortgage_start)
      day_before = start - 1.day
      valuation!(@current, "opening_anchor", 6_400, day_before)
      valuation!(@savings, "opening_anchor", 17_500, day_before)

      # The flat was bought with the mortgage; it is worth more today.
      valuation!(@flat, "opening_anchor", 225_000, mortgage_start)
      valuation!(@flat, "current_anchor", 268_000, today)

      # The car loses value: bought for 21.900 €, worth about 13.500 € now.
      valuation!(@car, "opening_anchor", 21_900, @car.vehicle.purchase_date)
      valuation!(@car, "current_anchor", 13_500, today)

      # The mortgage opens at its principal (initial_balance, which the
      # amortisation schedule starts from). The years before the example data are
      # summed up in one reconciliation at what the schedule says is left.
      valuation!(@mortgage, "opening_anchor", 180_000, mortgage_start)
      # Reloaded: the Loan built with the account does not know its account
      # yet, and the schedule needs it.
      @mortgage.reload
      left = @mortgage.loan.amortization_schedule.payments.select { |p| p.date < start }.last
      valuation!(@mortgage, "reconciliation", left.ending_balance.amount.round(2), day_before) if left
    end

    def valuation!(account, kind, amount, date)
      name = case kind
      when "opening_anchor" then Valuation.build_opening_anchor_name(account.accountable_type)
      when "current_anchor" then Valuation.build_current_anchor_name(account.accountable_type)
      else Valuation.build_reconciliation_name(account.accountable_type)
      end
      account.entries.create!(entryable: Valuation.new(kind: kind), amount: amount, name: name, currency: "EUR", date: date)
    end

    # ------------------------------------------------------------- movements

    def create_movements!
      @fuel_charges = []
      @service_charges = []
      @card_by_month = Hash.new(0)

      each_month do |month|
        income!(month)
        bills!(month)
        everyday_spending!(month)
        seasonal!(month)
        savings_and_investments!(month)
      end
      yearly_and_one_off!
      mortgage_payments!
      card_payments!
      prices!
    end

    def each_month
      month = start
      while month <= today
        yield month
        month = month.next_month
      end
    end

    def income!(month)
      # Two salaries, and the extra pays in June and December.
      add(@current, on(month, 28), -2_460, "Nómina Lucía - Laboralia SL", "Nómina")
      add(@current, on(month, 1), -1_985, "Nómina Javier - Clínica Dental Sonrisa", "Nómina")
      if [ 6, 12 ].include?(month.month)
        add(@current, on(month, 22), -2_460, "Paga extra Lucía - Laboralia SL", "Nómina")
        add(@current, on(month, 20), -1_985, "Paga extra Javier - Clínica Dental Sonrisa", "Nómina")
      end
      add(@savings, month.end_of_month, -(13 + rand(4)).to_f, "Intereses cuenta ahorro", "Intereses y dividendos")
      add(@current, on(month, rand(8..24)), -[ 15, 20, 25, 30 ].sample(random: @rng), "Bizum de Marta (cena)", "Otros Ingresos") if month.month.even?
    end

    def bills!(month)
      add(@current, on(month, 5), 78, "Recibo comunidad de propietarios", "Comunidad", flat: "community")
      add(@current, on(month, 12), vary(winter?(month) ? 92 : 58, 0.12), "Recibo luz Iberdrola", "Energía y suministros", flat: "utilities")
      add(@current, on(month, 18), vary(winter?(month) ? 64 : 24, 0.15), "Recibo gas Naturgy", "Energía y suministros", flat: "utilities")
      add(@current, on(month, 9), vary(41, 0.08), "Recibo agua Canal de Isabel II", "Energía y suministros", flat: "utilities") if month.month.odd?
      add(@current, on(month, 8), 64.90, "Recibo Movistar Fusión", "Teléfono")
      add(@current, on(month, 3), 39.90, "Cuota gimnasio Basic-Fit", "Gimnasio")
      add(@current, on(month, 6), 185, "Cuota colegio Los Pinos", "Educación y colegio") unless [ 7, 8 ].include?(month.month)
      add(@current, on(month, 7), 45, "Escuela de música - clases", "Aficiones y actividades") unless [ 7, 8 ].include?(month.month)
      add(@card, on(month, 15), 13.99, "Netflix", "TV, películas, música y streaming")
      add(@card, on(month, 20), 17.99, "Spotify Familiar", "TV, películas, música y streaming")
      add(@current, on(month, 25), 60, "Retirada cajero", "Excluido")
    end

    def everyday_spending!(month)
      days = month_days(month)

      rand(7..9).times do
        shop = %w[Mercadona Carrefour Lidl Dia Alcampo].sample(random: @rng)
        add(@card, days.sample(random: @rng), vary(rand(35..115), 0.1), shop, "Supermercado")
      end
      rand(3..5).times do
        place = [ "Restaurante La Tagliatella", "Foster's Hollywood", "Bar El Rincón", "Just Eat", "Glovo", "Taberna La Bola" ].sample(random: @rng)
        add(@card, days.sample(random: @rng), vary(rand(18..72), 0.1), place, "Restaurantes y comida a domicilio")
      end
      rand(4..7).times do
        add(@card, days.sample(random: @rng), vary(rand(2..7), 0.1), [ "Cafetería Central", "Starbucks", "Panadería Paco" ].sample(random: @rng), "Café y aperitivos")
      end
      rand(2..4).times do
        add(@card, days.sample(random: @rng), vary(rand(8..26), 0.1), [ "Cervecería La Sureña", "Bar Casa Paco" ].sample(random: @rng), "Cañas y vinos")
      end

      # Refuels every ten days or so; the logbook gets km and litres later.
      [ 3, 13, 23 ].each do |day|
        date = on(month, day + rand(-2..2))
        next if date > today

        station = %w[Repsol Cepsa BP Galp Ballenoil].sample(random: @rng)
        @fuel_charges << add(@card, date, vary(58, 0.15), "Gasolinera #{station}", "Combustible")
      end

      add(@card, days.sample(random: @rng), vary(9, 0.3), "Parking EMT Madrid", "Aparcamiento", car: "parking") if rand < 0.8
      add(@card, days.sample(random: @rng), 20, "Abono transporte Consorcio", "Transporte público")
      add(@card, days.sample(random: @rng), vary(rand(9..28), 0.1), "Farmacia Gran Vía", "Farmacia") if rand < 0.7
      add(@card, days.sample(random: @rng), vary(rand(25..85), 0.1), %w[Zara Mango Primark].sample(random: @rng), "Ropa y accesorios") if rand < 0.75
      add(@card, days.sample(random: @rng), vary(rand(12..55), 0.1), "Amazon.es", "Otras Compras") if rand < 0.8
      add(@card, days.sample(random: @rng), 19.80, "Cines Yelmo", "Entradas") if rand < 0.6
      add(@card, days.sample(random: @rng), vary(rand(15..40), 0.1), "Decathlon", "Fitness y deporte") if rand < 0.3
      add(@card, days.sample(random: @rng), vary(rand(20..45), 0.1), "Kiabi - ropa niños", "Ropa") if rand < 0.4
    end

    def seasonal!(month)
      case month.month
      when 8
        add(@card, on(month, 2), 685, "Booking.com - Apartamento Conil", "Vacaciones y viajes")
        add(@card, on(month, 2), vary(52, 0.1), "Autopista AP-4 peaje", "Peajes", car: "toll")
        add(@card, on(month, 9), vary(48, 0.1), "Autopista AP-4 peaje", "Peajes", car: "toll")
        3.times { add(@card, on(month, rand(3..9)), vary(rand(30..80), 0.1), "Chiringuito El Palmar", "Restaurantes y comida a domicilio") }
      when 12
        3.times { add(@card, on(month, rand(10..23)), vary(rand(35..110), 0.1), "El Corte Inglés", "Regalos (compras)") }
        add(@card, on(month, 15), 40, "Lotería de Navidad", "Lotería y juegos de azar")
        add(@card, on(month, 26), vary(65, 0.1), "Juguettos", "Juguetes y electrónica")
      when 4
        add(@card, on(month, 10), 128, "Renfe AVE Madrid - Sevilla", "Larga distancia")
      when 9
        add(@card, on(month, 5), 164, "Libros y material escolar", "Educación y colegio")
      end
    end

    def savings_and_investments!(month)
      transfer!(@current, @savings, 300, on(month, 29))
      contribution!(month)
    end

    # The fund gets 200 € a month, bought at that day's price.
    def contribution!(month)
      date = on(month, 2)
      return if date > today

      transfer!(@current, @fund, 200, date)
      buy!(@fund, security(:fund), 200, date)
    end

    def card_payments!
      @card_by_month.sort.each do |month, total|
        date = on(month.next_month, 3)
        next if date > today || total.zero?

        transfer!(@current, @card, total.round(2), date)
      end
    end

    def mortgage_payments!
      @mortgage.loan.amortization_schedule.payments.each do |payment|
        next if payment.date < start
        break if payment.date > today

        transfer = transfer!(@current, @mortgage, payment.principal.amount.round(2), payment.date)
        add(@current, payment.date, payment.interest.amount.round(2), "Intereses préstamo hipotecario", "Préstamos e intereses")
        flat_expense!("mortgage", transfer.outflow_transaction.entry, notes: "Recibo de la hipoteca")
      end
    end

    def yearly_and_one_off!
      add(@current, latest(3, 20), 285, "Mapfre - seguro hogar", "Seguro de hogar", flat: "insurance")
      add(@current, latest(10, 4), 412, "Ayuntamiento de Madrid - IBI", "Impuestos", flat: "tax")
      add(@current, latest(6, 14), 1_480, "Reformas Hermanos López - baño", "Reformas y construcción", flat: "renovation")
      add(@card, latest(11, 9), 349, "IKEA - armario dormitorio", "Muebles y decoración", flat: "furniture")

      @car_insurance = add(@current, latest(2, 11), 418, "Mutua Madrileña - seguro coche", "Seguro del vehículo")
      @road_tax = add(@current, latest(4, 2), 96, "Ayuntamiento de Madrid - impuesto vehículos", "Impuestos")
      @inspection = add(@card, latest(5, 21), 42.50, "Estación ITV Alcobendas", "Vehículo y mantenimiento")
      @service_charges << [ add(@card, (today << 7).change(day: 16), 189, "Norauto - cambio de aceite y filtros", "Vehículo y mantenimiento"), "Cambio de aceite" ]
      @service_charges << [ add(@card, (today << 11).change(day: 8), 146, "Norauto - pastillas de freno", "Vehículo y mantenimiento"), "Pastillas de freno" ]

      add(@current, latest(6, 30), -640, "Agencia Tributaria - devolución IRPF", "Devolución de impuestos")
      add(@card, (today << 3).change(day: 12), 90, "Clínica Dental Sonrisa - revisión", "Dentista")

      # Shares bought with part of the savings when the example data starts,
      # and their dividends.
      transfer!(@savings, @broker, 6_000, start)
      buy!(@broker, security(:bbva), 2_600, start)
      buy!(@broker, security(:san), 1_500, start)
      buy!(@broker, security(:ibe), 1_900, start)
      [ 4, 10 ].each do |m|
        dividend!(@broker, security(:bbva), 58, latest(m, 15))
        dividend!(@broker, security(:san), 31, latest(m, 2))
      end
      dividend!(@broker, security(:ibe), 44, latest(1, 30))
    end

    # The latest date with that month and day that falls in the example data.
    def latest(month_number, day)
      [ today.year, today.year - 1 ].map { |year| Date.new(year, month_number, day) }
                                    .find { |date| date <= today && date >= start } || start
    end

    # ------------------------------------------------------------ securities

    SECURITIES = {
      fund: { ticker: "IWDA", name: "iShares Core MSCI World UCITS ETF", mic: "XAMS", from: 86.0, to: 104.0 },
      bbva: { ticker: "BBVA", name: "Banco Bilbao Vizcaya Argentaria", mic: "XMAD", from: 9.2, to: 12.9 },
      san: { ticker: "SAN", name: "Banco Santander", mic: "XMAD", from: 4.3, to: 6.4 },
      ibe: { ticker: "IBE", name: "Iberdrola", mic: "XMAD", from: 12.6, to: 15.8 }
    }.freeze

    # Securities are shared by every family, so an existing one is reused.
    def security(key)
      @securities ||= {}
      @securities[key] ||= begin
        spec = SECURITIES.fetch(key)
        Security.where("upper(ticker) = ? AND exchange_operating_mic = ?", spec[:ticker], spec[:mic]).first ||
          Security.create!(ticker: spec[:ticker], name: spec[:name], exchange_operating_mic: spec[:mic], country_code: "ES")
      end
    end

    # A smooth path from `from` to `to` with a little noise, one price per
    # weekday. The same seed always gives the same prices.
    def price_on(key, date)
      @price_paths ||= {}
      path = @price_paths[key] ||= begin
        spec = SECURITIES.fetch(key)
        days = (start - 7.days..today).to_a
        noise = 0.0
        days.each_with_index.to_h do |day, i|
          noise = (noise * 0.9) + @rng.rand(-0.012..0.012)
          trend = spec[:from] + ((spec[:to] - spec[:from]) * i / (days.size - 1).to_f)
          [ day, (trend * (1 + noise)).round(2) ]
        end
      end
      path.fetch(date) { path.values.last }
    end

    # Prices for the holdings to be valued every day. Days a provider already
    # filled in are kept.
    def prices!
      SECURITIES.each_key do |key|
        sec = security(key)
        rows = (start - 7.days..today).reject { |d| d.saturday? || d.sunday? }.map do |date|
          { security_id: sec.id, date: date, price: price_on(key, date), currency: "EUR" }
        end
        Security::Price.insert_all(rows, unique_by: :index_security_prices_on_security_id_and_date_and_currency)
      end
    end

    def buy!(account, sec, amount, date)
      key = SECURITIES.find { |_k, spec| spec[:ticker] == sec.ticker.upcase }&.first
      price = price_on(key, date)
      qty = (amount / price).round(4)
      account.entries.create!(
        name: "Compra #{qty.to_s.tr('.', ',')} #{sec.ticker}",
        date: date,
        amount: (qty * price).round(2),
        currency: "EUR",
        entryable: Trade.new(qty: qty, price: price, fee: 0, currency: "EUR", security: sec, investment_activity_label: "Buy")
      )
    end

    def dividend!(account, sec, amount, date)
      return if date > today

      account.entries.create!(
        name: "Dividendo #{sec.ticker}",
        date: date,
        amount: -amount,
        currency: "EUR",
        entryable: Trade.new(qty: 0, price: 0, fee: 0, currency: "EUR", security: sec, investment_activity_label: "Dividend")
      )
    end

    # --------------------------------------------------- car and flat records

    def car_logbook!
      vehicle = @car.vehicle
      odometer = 61_400
      charges = @fuel_charges.sort_by(&:date)
      # The two latest refuels are left for the app to propose.
      pending = charges.last(2)

      charges.each do |entry|
        odometer += rand(520..690)
        next if pending.include?(entry)

        price = (1.56 + rand * 0.14).round(3)
        vehicle.logs.create!(kind: "fuel", date: entry.date, entry: entry, odometer: odometer,
                             quantity: (entry.amount / price).round(2), unit_price: price, full_tank: true)
      end

      oil = vehicle.maintenance_items.create!(name: "Cambio de aceite y filtros", interval_km: 15_000, interval_months: 12,
                                              notes: "Aceite 5W-30 sintético")
      brakes = vehicle.maintenance_items.create!(name: "Pastillas de freno", interval_km: 30_000)
      itv = vehicle.maintenance_items.create!(name: "ITV", interval_months: 24)
      vehicle.maintenance_items.create!(name: "Neumáticos", interval_km: 40_000, last_done_odometer: 52_300,
                                        last_done_on: start - 3.months, notes: "Michelin Primacy 4, 225/45 R17")

      { "Cambio de aceite" => oil, "Pastillas de freno" => brakes }.each do |label, item|
        entry = @service_charges.find { |_e, l| l == label }&.first
        next unless entry

        vehicle.logs.create!(kind: "service", date: entry.date, entry: entry, maintenance_item: item,
                             odometer: odometer_on(entry.date), notes: entry.name.split(" - ").last.capitalize)
      end
      vehicle.logs.create!(kind: "expense", category: "inspection", date: @inspection.date, entry: @inspection,
                           maintenance_item: itv, odometer: odometer_on(@inspection.date), notes: "ITV favorable")
      vehicle.logs.create!(kind: "expense", category: "insurance", date: @car_insurance.date, entry: @car_insurance,
                           notes: "Todo riesgo con franquicia")
      vehicle.logs.create!(kind: "expense", category: "road_tax", date: @road_tax.date, entry: @road_tax)
      Array(@car_expenses).each do |category, entry|
        vehicle.logs.create!(kind: "expense", category: category, date: entry.date, entry: entry)
      end
    end

    # The odometer reading closest before a date, from the refuels.
    def odometer_on(date)
      @car.vehicle.logs.fuels.where(date: ..date).order(:date).last&.odometer || 61_400
    end

    def flat_expense!(kind, entry, notes: nil)
      @flat_expenses ||= []
      @flat_expenses << [ kind, entry, notes ]
    end

    def flat_records!
      property = @flat.property
      # The latest community fee is left for the app to propose.
      latest_community = @flat_expenses.select { |kind, _e, _n| kind == "community" }.max_by { |_k, e, _n| e.date }
      (@flat_expenses - [ latest_community ]).each do |kind, entry, notes|
        property.expenses.create!(kind: kind, date: entry.date, entry: entry, notes: notes)
      end
    end

    # ---------------------------------------------- budgets and the forecast

    BUDGETS = {
      "Comida y bebida" => 700,
      "Transporte" => 260,
      "Ocio y entretenimiento" => 220,
      "Compras" => 180,
      "Niños" => 300,
      "Salud y educación" => 110,
      "Hogar" => 320
    }.freeze

    def create_budgets!
      3.times do |back|
        month = (today << back).beginning_of_month
        budget = family.budgets.create!(start_date: month, end_date: month.end_of_month, currency: "EUR",
                                        budgeted_spending: BUDGETS.values.sum, expected_income: 4_445)
        BUDGETS.each do |name, amount|
          budget.budget_categories.create!(category: category(name), budgeted_spending: amount, currency: "EUR")
        end
      end
    end

    def create_forecast_items!
      family.forecast_items.create!(account: @current, name: "Revisión 90.000 km (taller)", amount: 320, currency: "EUR",
                                    date: (today >> 2).change(day: 10), nature: "outflow")
      family.forecast_items.create!(account: @current, name: "Viaje Semana Santa", amount: 750, currency: "EUR",
                                    date: (today >> 5).change(day: 1), nature: "outflow")
    end

    # ------------------------------------------------------------- finishing

    # Balances, holdings and the rest are worked out by syncing each account,
    # as after an import. Then the app looks for recurring payments and for
    # the charges left unlinked, as it does on its own after a sync.
    def finish!
      family.accounts.each { |account| Sync.create!(syncable: account).perform }

      RecurringTransaction::Pipeline.new(family).run!(backfill: true)
      AssetLinker.new(family, since: nil).run!
    end

    # --------------------------------------------------------------- helpers

    def add(account, date, amount, name, category_name, flat: nil, car: nil)
      return if date > today || date < start

      entry = account.entries.create!(
        entryable: Transaction.new(category: category(category_name)),
        amount: amount.to_d.round(2),
        name: name,
        currency: "EUR",
        date: date
      )
      @card_by_month[date.beginning_of_month] += entry.amount if account == @card
      flat_expense!(flat, entry) if flat
      (@car_expenses ||= []) << [ car, entry ] if car
      entry
    end

    def transfer!(from, to, amount, date)
      return if date > today

      Transfer::Creator.new(family: family, source_account_id: from.id, destination_account_id: to.id,
                            date: date, amount: amount).create
    end

    def category(name)
      @categories ||= family.categories.index_by(&:name)
      @categories.fetch(name)
    end

    # A day of that month, moved into the month when it does not exist.
    def on(month, day)
      month.change(day: day.clamp(1, month.end_of_month.day))
    end

    def month_days(month)
      (month..[ month.end_of_month, today ].min).to_a
    end

    def winter?(month)
      [ 11, 12, 1, 2, 3 ].include?(month.month)
    end

    def vary(amount, pct)
      (amount * (1 + (@rng.rand * 2 - 1) * pct)).round(2)
    end

    def rand(*args)
      @rng.rand(*args)
    end
end
