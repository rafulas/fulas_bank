class ConvertPropertyAreasToSquareMeters < ActiveRecord::Migration[8.1]
  # Fulas Bank measures properties in square metres only.
  SQFT_PER_SQM = 10.7639

  def up
    execute <<~SQL
      UPDATE properties
      SET area_value = ROUND(area_value / #{SQFT_PER_SQM}), area_unit = 'sqm'
      WHERE area_unit = 'sqft' AND area_value IS NOT NULL
    SQL
    execute "UPDATE properties SET area_unit = 'sqm' WHERE area_unit IS NULL OR area_unit = 'sqft'"
  end

  def down
    # Areas stay in square metres.
  end
end
