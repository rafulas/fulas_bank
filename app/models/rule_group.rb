# Fulas Bank: a named group of rules ("Supermercados", "Coche"...), to find
# them on the rules page. Deleting one leaves its rules without a group.
class RuleGroup < ApplicationRecord
  belongs_to :family
  has_many :rules, dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.squish }

  validates :name, presence: true, uniqueness: { scope: :family_id, case_sensitive: false }

  scope :alphabetically, -> { order(Arel.sql("LOWER(name)")) }
end
