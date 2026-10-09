# A bank charge the user said does not belong to a vehicle or property
# account, so AssetLinker does not propose it for that account again.
class AssetLinkRejection < ApplicationRecord
  belongs_to :entry
  belongs_to :account

  validates :entry_id, uniqueness: { scope: :account_id }
end
