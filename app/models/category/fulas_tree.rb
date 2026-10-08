# Fulas Bank's own category tree (categories and subcategories), in Spanish.
#
# `apply!` is idempotent and safe to run on a family that already has data:
#   1. Folds Sure's old default categories (in any supported locale) into
#      their new equivalent, moving their transactions and budgets with them.
#   2. Creates every missing category and puts existing ones with the same
#      name under the right parent, with the tree's color and icon.
# Categories the user created that are not in the tree are left untouched.
#
# Two root categories have special behavior (see Transaction):
#   - "Excluido": its transactions are excluded from reports and budgets.
#   - "Traspasos": its transactions are kept out of income/expense analytics.
#
# Category names are unique per family, so the four "Regalos" subcategories
# carry a short qualifier.
class Category::FulasTree
  EXCLUDED_NAME = "Excluido".freeze
  TRANSFERS_NAME = "Traspasos".freeze
  OTHER_NAME = "Otros".freeze

  # [ name, color, icon, [ [ subcategory name, icon ], ... ] ]
  TREE = [
    [ "Salud y educación", "#e0875a", "heart-pulse", [
      [ "Atención médica", "stethoscope" ],
      [ "Gimnasio", "dumbbell" ],
      [ "Fitness y deporte", "bike" ],
      [ "Farmacia", "pill" ],
      [ "Bienestar y estética", "sparkles" ],
      [ "Educación y desarrollo personal", "book-open" ],
      [ "Dentista", "shield-plus" ]
    ] ],
    [ "Hogar", "#a3b43a", "home", [
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
    [ "Gastos financieros", "#c4605f", "landmark", [
      [ "Seguros", "shield" ],
      [ "Préstamos e intereses", "banknote" ],
      [ "Cargos y comisiones", "receipt" ],
      [ "Impuestos", "percent" ],
      [ "Multas", "receipt-text" ],
      [ "Asesoramiento", "calculator" ]
    ] ],
    [ "Comida y bebida", "#4fae42", "apple", [
      [ "Supermercado", "shopping-cart" ],
      [ "Restaurantes y comida a domicilio", "utensils" ],
      [ "Café y aperitivos", "coffee" ],
      [ "Cañas y vinos", "beer" ],
      [ "Alcohol y tabaco", "wine" ]
    ] ],
    [ "Transporte", "#5470dc", "car", [
      [ "Combustible", "fuel" ],
      [ "Aparcamiento", "circle-parking" ],
      [ "Leasing", "calendar-range" ],
      [ "Peajes", "badge-dollar-sign" ],
      [ "Alquileres", "key" ],
      [ "Vehículo y mantenimiento", "settings" ],
      [ "Seguro del vehículo", "shield" ],
      [ "Transporte público", "bus" ],
      [ "Taxi", "car" ],
      [ "Accesorios Vehículos", "package" ],
      [ "Larga distancia", "plane" ]
    ] ],
    [ "Ocio y entretenimiento", "#45a0e6", "drama", [
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
    [ "Compras", "#2e9e7a", "shopping-basket", [
      [ "Otras Compras", "shopping-bag" ],
      [ "Ropa y accesorios", "shirt" ],
      [ "Regalos (compras)", "gift" ],
      [ "Productos de belleza", "flower" ],
      [ "Electrónica", "laptop" ]
    ] ],
    [ TRANSFERS_NAME, "#7779a6", "arrow-left-right", [] ],
    [ "Ingresos", "#f0a93a", "briefcase", [
      [ "Nómina", "banknote" ],
      [ "Regalos recibidos", "gift" ],
      [ "Otros Ingresos", "circle-dollar-sign" ],
      [ "Intereses y dividendos", "percent" ],
      [ "Ventas", "store" ],
      [ "Devolución de impuestos", "landmark" ],
      [ "Herencia", "gem" ],
      [ "Venta Acciones", "trending-up" ]
    ] ],
    [ "Inversiones", "#ae4be0", "chart-line", [
      [ "Inversiones financieras", "trending-up" ],
      [ "Planes de pensiones", "landmark" ],
      [ "Ahorros", "piggy-bank" ],
      [ "Bienes inmuebles", "building" ]
    ] ],
    [ OTHER_NAME, "#a06a50", "tag", [] ],
    [ "Niños", "#d45e8b", "baby", [
      [ "Ropa", "shirt" ],
      [ "Pensión de alimentos y compensatoria", "scale" ],
      [ "Salud", "thermometer" ],
      [ "Paga", "coins" ],
      [ "Juguetes y electrónica", "gamepad-2" ],
      [ "Regalos (niños)", "gift" ],
      [ "Canguro", "users" ],
      [ "Educación y colegio", "graduation-cap" ],
      [ "Aficiones y actividades", "trophy" ]
    ] ],
    [ EXCLUDED_NAME, "#a8a6b0", "ban", [] ]
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
    "services" => OTHER_NAME,
    "fees" => "Cargos y comisiones",
    "savings_and_investments" => "Inversiones"
  }.freeze

  # Root categories with no subcategories.
  LEAF_ROOTS = [ OTHER_NAME, EXCLUDED_NAME, TRANSFERS_NAME ].freeze

  class << self
    def names
      TREE.flat_map { |name, _color, _icon, children| [ name ] + children.map(&:first) }
    end

    def excluded?(category)
      root_named?(category, EXCLUDED_NAME)
    end

    def transfers?(category)
      root_named?(category, TRANSFERS_NAME)
    end

    private
      def root_named?(category, name)
        category.present? && category.parent_id.nil? && category.name == name
      end
  end

  attr_reader :family

  def initialize(family)
    @family = family
  end

  def apply!
    Category.transaction do
      fold_legacy_categories!
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
          # Already a tree category in its place (e.g. "Salud" under "Niños"
          # on a second run), not a leftover default.
          next if in_tree_position?(legacy)

          target = ensure_category!(target_name)
          next if target.id == legacy.id

          begin
            Category::Merger.new(family: family, target_category: target, source_categories: [ legacy ]).merge!
          rescue Category::Merger::UnauthorizedCategoryError
            # e.g. the old category has its own subcategories and the target is
            # a subcategory: leave it for the user to sort out by hand.
            next
          end
        end
      end
    end

    def build_tree!
      TREE.each do |name, color, icon, children|
        parent = upsert!(name, color: color, icon: icon, parent: nil)

        children.each do |child_name, child_icon|
          upsert!(child_name, color: color, icon: child_icon, parent: parent)
        end
      end
    end

    # Finds a tree category by name, creating it (and its parent) in place.
    def ensure_category!(name)
      TREE.each do |root_name, color, icon, children|
        return upsert!(root_name, color: color, icon: icon, parent: nil) if root_name == name

        child = children.find { |child_name, _| child_name == name }
        next unless child

        parent = upsert!(root_name, color: color, icon: icon, parent: nil)
        return upsert!(name, color: color, icon: child.last, parent: parent)
      end

      raise ArgumentError, "#{name} is not part of the Fulas Bank category tree"
    end

    def upsert!(name, color:, icon:, parent:)
      category = categories.find_or_initialize_by(name: name)
      category.color = color
      category.lucide_icon = icon

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
      TREE.any? do |root_name, _color, _icon, children|
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
