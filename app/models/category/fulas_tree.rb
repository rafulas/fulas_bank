# Fulas Bank's default categories: 13 root categories, most with their
# subcategories, in Spanish. They are the starting point for every family,
# not a fixed structure: they can be renamed, restyled and extended.
#
# Three root categories carry a built-in behavior, recorded in
# `categories.special` (see Category):
#   - Otros      (other)     catch-all, counts like any other category
#   - Excluido   (excluded)  kept, but left out of reports and statistics
#   - Traspasos  (transfers) money between own accounts, not income/expense
#
# `apply!` is idempotent and safe on a family with data. It creates the
# missing categories and puts existing ones with a tree name under the right
# parent. Specials are found by their marker, so a renamed "Excluido" is
# still found. Categories the family created that aren't in the tree are left
# untouched.
#
# `apply!(first_rollout: true)` is used once, when the tree replaces Sure's
# defaults in an existing family: it also folds Sure's old default categories
# (in any supported locale) into their new equivalent, moving their
# transactions and budgets with them, and resets the color, icon and order of
# the tree's categories.
#
# Category names are unique per family, so the four "Regalos" subcategories
# carry a short qualifier.
class Category::FulasTree
  # [ name, color, icon, special, [ [ subcategory name, icon ], ... ] ]
  TREE = [
    [ "Salud y educación", "#d88450", "heart-pulse", nil, [
      [ "Atención médica", "stethoscope" ],
      [ "Gimnasio", "dumbbell" ],
      [ "Fitness y deporte", "bike" ],
      [ "Farmacia", "pill" ],
      [ "Bienestar y estética", "sparkles" ],
      [ "Educación y desarrollo personal", "book-open" ],
      [ "Dentista", "shield-plus" ]
    ] ],
    [ "Hogar", "#b0bc3c", "home", nil, [
      [ "Comunidad", "building" ],
      [ "Seguridad", "video" ],
      [ "Alquiler e hipoteca", "house" ],
      [ "Energía y suministros", "lightbulb" ],
      [ "Muebles y decoración", "bed-single" ],
      [ "Limpieza del hogar", "bath" ],
      [ "Reformas y construcción", "hammer" ],
      [ "Mantenimiento y reparaciones", "wrench" ],
      [ "Seguro de hogar", "umbrella" ],
      [ "Jardín y plantas", "sprout" ]
    ] ],
    [ "Gastos financieros", "#b86460", "badge-dollar-sign", nil, [
      [ "Seguros", "shield" ],
      [ "Préstamos e intereses", "banknote" ],
      [ "Cargos y comisiones", "receipt" ],
      [ "Impuestos", "landmark" ],
      [ "Multas", "receipt-text" ],
      [ "Asesoramiento", "calculator" ]
    ] ],
    [ "Comida y bebida", "#68b448", "apple", nil, [
      [ "Supermercado", "shopping-cart" ],
      [ "Restaurantes y comida a domicilio", "utensils" ],
      [ "Café y aperitivos", "coffee" ],
      [ "Cañas y vinos", "beer" ],
      [ "Alcohol y tabaco", "wine" ]
    ] ],
    [ "Transporte", "#506cd8", "car", nil, [
      [ "Combustible", "fuel" ],
      [ "Aparcamiento", "circle-parking" ],
      [ "Leasing", "calendar-range" ],
      [ "Peajes", "coins" ],
      [ "Alquileres", "key" ],
      [ "Vehículo y mantenimiento", "wrench" ],
      [ "Seguro del vehículo", "shield" ],
      [ "Transporte público", "bus" ],
      [ "Taxi", "car" ],
      [ "Accesorios Vehículos", "package" ],
      [ "Larga distancia", "plane" ]
    ] ],
    [ "Ocio y entretenimiento", "#489ce0", "drama", nil, [
      [ "Teléfono", "phone" ],
      [ "Cuotas Socio", "wallet-cards" ],
      [ "Donaciones", "hand-heart" ],
      [ "Vacaciones y viajes", "tree-palm" ],
      [ "Servicios digitales", "plug" ],
      [ "TV, películas, música y streaming", "tv" ],
      [ "Fiestas", "party-popper" ],
      [ "Entradas", "ticket" ],
      [ "Lotería y juegos de azar", "dices" ],
      [ "Aficiones", "puzzle" ],
      [ "Regalos", "gift" ],
      [ "Cultura y eventos", "palette" ],
      [ "Celebraciones", "cake" ],
      [ "Libros, audiolibros y noticias", "book" ]
    ] ],
    [ "Compras", "#449c78", "shopping-basket", nil, [
      [ "Otras Compras", "shopping-bag" ],
      [ "Ropa y accesorios", "shirt" ],
      [ "Regalos (compras)", "gift" ],
      [ "Productos de belleza", "flower" ],
      [ "Electrónica", "laptop" ]
    ] ],
    [ "Traspasos", "#7c7ca0", "arrow-right-left", "transfers", [] ],
    [ "Ingresos", "#e8a838", "briefcase", nil, [
      [ "Nómina", "banknote" ],
      [ "Regalos recibidos", "gift" ],
      [ "Otros Ingresos", "briefcase" ],
      [ "Intereses y dividendos", "percent" ],
      [ "Ventas", "store" ],
      [ "Devolución de impuestos", "landmark" ],
      [ "Herencia", "gem" ],
      [ "Venta Acciones", "trending-up" ]
    ] ],
    [ "Inversiones", "#a448d8", "chart-line", nil, [
      [ "Inversiones financieras", "trending-up" ],
      [ "Planes de pensiones", "landmark" ],
      [ "Ahorros", "piggy-bank" ],
      [ "Bienes inmuebles", "building" ]
    ] ],
    [ "Otros", "#a46c54", "layout-grid", "other", [] ],
    [ "Niños", "#c86084", "baby", nil, [
      [ "Ropa", "shirt" ],
      [ "Pensión de alimentos y compensatoria", "scale" ],
      [ "Salud", "stethoscope" ],
      [ "Paga", "coins" ],
      [ "Juguetes y electrónica", "gamepad-2" ],
      [ "Regalos (niños)", "gift" ],
      [ "Canguro", "users" ],
      [ "Educación y colegio", "graduation-cap" ],
      [ "Aficiones y actividades", "trophy" ]
    ] ],
    [ "Excluido", "#bcbcc0", "eye-off", "excluded", [] ]
  ].freeze

  # Sure's previous default categories (by i18n key) and where they go now.
  LEGACY_TARGETS = {
    "income" => "Ingresos",
    "food_and_drink" => "Comida y bebida",
    "groceries" => "Supermercado",
    "shopping" => "Compras",
    "transportation" => "Transporte",
    "travel" => "Vacaciones y viajes",
    "entertainment" => "Ocio y entretenimiento",
    "healthcare" => "Atención médica",
    "personal_care" => "Bienestar y estética",
    "home_improvement" => "Reformas y construcción",
    "mortgage_rent" => "Alquiler e hipoteca",
    "utilities" => "Energía y suministros",
    "subscriptions" => "Servicios digitales",
    "insurance" => "Seguros",
    "sports_and_fitness" => "Fitness y deporte",
    "gifts_and_donations" => "Donaciones",
    "taxes" => "Impuestos",
    "loan_payments" => "Préstamos e intereses",
    "services" => "Otros",
    "fees" => "Cargos y comisiones",
    "savings_and_investments" => "Inversiones"
  }.freeze

  class << self
    def names
      TREE.flat_map { |name, _color, _icon, _special, children| [ name ] + children.map(&:first) }
    end
  end

  attr_reader :family

  def initialize(family)
    @family = family
  end

  # Without `first_rollout`, only new categories get the tree's appearance and
  # order, so a family's own changes are kept.
  def apply!(first_rollout: false)
    @restyle = first_rollout

    Category.transaction do
      fold_legacy_categories! if first_rollout
      build_tree!
    end
  end

  private
    def fold_legacy_categories!
      LEGACY_TARGETS.each do |key, target_name|
        legacy_names_for(key).each do |legacy_name|
          next if legacy_name == target_name

          legacy = categories.find_by(name: legacy_name)
          next unless legacy
          # Already a tree category in its place (e.g. "Salud" under "Niños"),
          # not a leftover default.
          next if in_tree_position?(legacy) || legacy.special?

          target = ensure_category!(target_name)
          next if target.id == legacy.id

          begin
            Category::Merger.new(family: family, target_category: target, source_categories: [ legacy ]).merge!
          rescue Category::Merger::UnauthorizedCategoryError
            # e.g. the old category has its own subcategories and the target is
            # a subcategory: leave it for the family to sort out by hand.
            next
          end
        end
      end
    end

    def build_tree!
      TREE.each_with_index do |(name, color, icon, special, children), index|
        parent = upsert!(name, color: color, icon: icon, special: special, parent: nil, position: index + 1)

        children.each_with_index do |(child_name, child_icon), child_index|
          upsert!(child_name, color: color, icon: child_icon, special: nil, parent: parent, position: child_index + 1)
        end
      end
    end

    # Finds a tree category by name, creating it (and its parent) in place.
    def ensure_category!(name)
      TREE.each_with_index do |(root_name, color, icon, special, children), index|
        root = -> { upsert!(root_name, color: color, icon: icon, special: special, parent: nil, position: index + 1) }
        return root.call if root_name == name

        child_index = children.index { |child_name, _| child_name == name }
        next unless child_index

        return upsert!(name, color: color, icon: children[child_index].last, special: nil, parent: root.call, position: child_index + 1)
      end

      raise ArgumentError, "#{name} is not part of the Fulas Bank category tree"
    end

    def upsert!(name, color:, icon:, special:, parent:, position:)
      category = (special && categories.find_by(special: special)) || categories.find_or_initialize_by(name: name)
      fresh = category.new_record?

      if fresh || @restyle
        category.color = color
        category.lucide_icon = icon
        category.position = position
      end
      category.special = special if special

      # A category that already has subcategories can't become one itself.
      unless parent && category.persisted? && category.parent?
        category.parent = parent
      end

      category.save!
      category
    end

    def categories
      family.categories
    end

    def in_tree_position?(category)
      TREE.any? do |root_name, _color, _icon, _special, children|
        if category.parent_id.nil?
          root_name == category.name
        else
          category.parent&.name == root_name && children.any? { |child_name, _| child_name == category.name }
        end
      end
    end

    def legacy_names_for(key)
      LanguagesHelper::SUPPORTED_LOCALES.filter_map do |locale|
        I18n.t("models.category.defaults.#{key}", locale: locale, default: nil)
      end.uniq
    end
end
