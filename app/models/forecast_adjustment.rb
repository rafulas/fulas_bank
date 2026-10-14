# A change the user makes in the forecast table to a line the app works out
# by itself: a recurring payment on a given date, or the variable spending of
# a month. It can give the line another date, amount or name, or leave it out
# (`skipped`). Empty fields keep the line's own value.
#
# The lines are recalculated every time, so the change is found again by the
# line's key:
#   recurring:<series id>:<the payment's original date, YYYY-MM-DD>
#   variable:<account id>:<the month, YYYY-MM>
# A change whose line no longer exists (the series ended, the month has
# passed) is simply ignored.
class ForecastAdjustment < ApplicationRecord
  UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}".freeze
  KEY_FORMAT = /\A(?:recurring:#{UUID}:\d{4}-\d{2}-\d{2}|variable:#{UUID}:\d{4}-\d{2})\z/

  belongs_to :family

  validates :key, presence: true, format: { with: KEY_FORMAT }, uniqueness: { scope: :family_id }
  validates :amount, numericality: { greater_than: 0 }, allow_nil: true
  validate :key_belongs_to_family

  def self.recurring_key(series, original_date)
    "recurring:#{series.id}:#{original_date.iso8601}"
  end

  def self.variable_key(account, month)
    "variable:#{account.id}:#{month.strftime('%Y-%m')}"
  end

  def self.valid_key?(key)
    key.is_a?(String) && key.match?(KEY_FORMAT)
  end

  def kind
    key.to_s.split(":").first
  end

  private
    # The key names a series or an account: it has to be one of this family's.
    def key_belongs_to_family
      return unless family && self.class.valid_key?(key)

      _, id, _ = key.split(":")
      exists = kind == "recurring" ? family.recurring_transactions.exists?(id) : family.accounts.exists?(id)
      errors.add(:key, :invalid) unless exists
    end
end
