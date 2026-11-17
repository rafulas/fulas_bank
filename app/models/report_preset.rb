# Fulas Bank: a saved way of opening the «Informe» (see StatusReport): its
# name, the accounts it covers, the sections it shows and its period.
class ReportPreset < ApplicationRecord
  belongs_to :user

  validates :name, presence: true, uniqueness: { scope: :user_id }, length: { maximum: 60 }
  validates :period, inclusion: { in: StatusReport::PERIODS }
  validate :known_sections

  scope :alphabetically, -> { order(:name) }

  private
    def known_sections
      errors.add(:sections, :invalid) if (Array(sections) - StatusReport::SECTIONS).any?
    end
end
