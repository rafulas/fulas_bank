# Fulas Bank: a «what if» of the Forecast ("Escenarios"). A named list of
# changes (ScenarioChange) applied on top of the forecast: stop a recurring
# payment, cancel a loan, change an amount, add an income or expense, or
# spend more or less every month. Nothing real is touched: the forecast is
# worked out twice, with and without the changes, and compared month by
# month (Scenario::Comparison).
class Scenario < ApplicationRecord
  belongs_to :family
  has_many :scenario_changes, -> { order(:starts_on, :created_at) }, dependent: :destroy, inverse_of: :scenario

  validates :name, presence: true

  scope :alphabetically, -> { order(:name) }

  # The day the first change takes effect.
  def starts_on
    scenario_changes.map(&:starts_on).min
  end
end
