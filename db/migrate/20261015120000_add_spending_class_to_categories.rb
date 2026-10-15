# Fulas Bank: necessary, discretionary or saving, for the 50/30/20 split
# (see Category::SpendingClass). Existing families get the app's proposal
# for the default categories; they can change it from the Resumen.
class AddSpendingClassToCategories < ActiveRecord::Migration[8.1]
  PROPOSAL = {
    "Salud y educación" => "essential", "Gimnasio" => "discretionary", "Fitness y deporte" => "discretionary",
    "Bienestar y estética" => "discretionary", "Hogar" => "essential", "Muebles y decoración" => "discretionary",
    "Jardín y plantas" => "discretionary", "Reformas y construcción" => "discretionary", "Gastos financieros" => "essential",
    "Comida y bebida" => "essential", "Restaurantes y comida a domicilio" => "discretionary",
    "Café y aperitivos" => "discretionary", "Cañas y vinos" => "discretionary", "Alcohol y tabaco" => "discretionary",
    "Transporte" => "essential", "Taxi" => "discretionary", "Alquileres" => "discretionary",
    "Accesorios Vehículos" => "discretionary", "Larga distancia" => "discretionary",
    "Ocio y entretenimiento" => "discretionary", "Teléfono" => "essential", "Compras" => "discretionary",
    "Niños" => "essential", "Juguetes y electrónica" => "discretionary", "Regalos (niños)" => "discretionary",
    "Aficiones y actividades" => "discretionary", "Inversiones" => "savings", "Otros" => "discretionary"
  }.freeze

  def up
    add_column :categories, :spending_class, :string
    add_check_constraint :categories, "spending_class IS NULL OR spending_class IN ('essential', 'discretionary', 'savings')",
                         name: "chk_categories_spending_class"

    # A copy of the proposal, so this migration does not depend on app code
    # that may change later.
    PROPOSAL.each do |name, spending_class|
      execute ActiveRecord::Base.sanitize_sql_array([
        "UPDATE categories SET spending_class = ? WHERE name = ? AND spending_class IS NULL", spending_class, name
      ])
    end
  end

  def down
    remove_check_constraint :categories, name: "chk_categories_spending_class"
    remove_column :categories, :spending_class
  end
end
