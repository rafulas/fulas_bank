class Measurement
  include ActiveModel::Validations

  attr_reader :value, :unit

  VALID_UNITS = %w[sqft sqm mi km]

  validates :unit, inclusion: { in: VALID_UNITS }
  validates :value, presence: true

  def initialize(value, unit)
    @value = value.to_f
    @unit = unit.to_s.downcase.strip
    validate!
  end

  # How each unit is written next to a value.
  SYMBOLS = { "sqft" => "ft²", "sqm" => "m²" }.freeze

  def to_s
    "#{@value.to_i} #{SYMBOLS.fetch(@unit, @unit)}"
  end
end
