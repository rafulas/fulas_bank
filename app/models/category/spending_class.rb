# Fulas Bank: whether spending in a category is necessary ("Necesario"),
# something that could be done without ("Prescindible") or saving
# ("Ahorro"), for the 50/30/20 split of the Resumen (Category::SpendingSplit).
#
# "income" marks the categories whose money in is income ("Ingresos"). Money
# in to any other category is a refund, which lowers that category's spending
# everywhere (Category::REFUND_IDS_SQL); a family with no "income" category
# keeps counting all money in as income.
#
# It is stored on each category (`categories.spending_class`). A subcategory
# without one takes its main category's, so only the exceptions need it: in
# "Comida y bebida" (necessary), "Restaurantes" and "Cañas y vinos" are set
# as discretionary.
#
# PROPOSAL is what the app suggests for the default categories (by name),
# applied when the categories are created and once to existing families.
module Category::SpendingClass
  CLASSES = %w[essential discretionary savings income].freeze

  # Main categories and the subcategories that differ from them.
  PROPOSAL = {
    "Salud y educación" => "essential",
    "Gimnasio" => "discretionary",
    "Fitness y deporte" => "discretionary",
    "Bienestar y estética" => "discretionary",
    "Hogar" => "essential",
    "Muebles y decoración" => "discretionary",
    "Jardín y plantas" => "discretionary",
    "Reformas y construcción" => "discretionary",
    "Gastos financieros" => "essential",
    "Comida y bebida" => "essential",
    "Restaurantes y comida a domicilio" => "discretionary",
    "Café y aperitivos" => "discretionary",
    "Cañas y vinos" => "discretionary",
    "Alcohol y tabaco" => "discretionary",
    "Transporte" => "essential",
    "Taxi" => "discretionary",
    "Alquileres" => "discretionary",
    "Accesorios Vehículos" => "discretionary",
    "Larga distancia" => "discretionary",
    "Ocio y entretenimiento" => "discretionary",
    "Teléfono" => "essential",
    "Compras" => "discretionary",
    "Niños" => "essential",
    "Juguetes y electrónica" => "discretionary",
    "Regalos (niños)" => "discretionary",
    "Aficiones y actividades" => "discretionary",
    "Inversiones" => "savings",
    "Otros" => "discretionary",
    "Ingresos" => "income"
  }.freeze

  module_function

  # Sets the proposal on the family's categories that have no class yet.
  def apply_proposal!(family)
    family.categories.where(spending_class: nil, name: PROPOSAL.keys).find_each do |category|
      category.update_columns(spending_class: PROPOSAL.fetch(category.name))
    end
  end
end
