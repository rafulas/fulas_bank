# Fulas Bank: the figures of the Seguros page. The policies in force, what
# they cost together, which renew soon, and which vehicles or properties have
# no policy in force tied to them.
class Insurance::Overview
  attr_reader :today

  def initialize(family, assets:, today: Date.current)
    @family = family
    @assets = assets
    @today = today
  end

  def insurances
    @insurances ||= @family.insurances.includes(account: :accountable).with_attached_documents.to_a
  end

  # In force, by kind (the order of Insurance::KINDS) and then by name.
  def active
    @active ||= insurances.select(&:active?).sort_by { |insurance| [ Insurance::KINDS.index(insurance.kind) || Insurance::KINDS.size, insurance.name.downcase ] }
  end

  def inactive
    @inactive ||= insurances.reject(&:active?).sort_by { |insurance| insurance.name.downcase }
  end

  def empty?
    insurances.empty?
  end

  def annual_total
    sum(active.filter_map(&:annual_cost))
  end

  def monthly_total
    sum(active.filter_map(&:monthly_cost))
  end

  # Policies in force whose renewal is within Insurance::RENEWAL_NOTICE,
  # soonest first.
  def renewing_soon
    active.select { |insurance| insurance.renews_soon?(today) }.sort_by { |insurance| insurance.next_renewal(today) }
  end

  def next_renewal
    active.select(&:renewal_date).min_by { |insurance| insurance.next_renewal(today) }
  end

  # The vehicles and properties with no policy in force tied to them.
  def uninsured_assets
    insured = active.filter_map(&:account_id)
    @assets.reject { |account| insured.include?(account.id) }
  end

  private
    def sum(amounts)
      return Money.new(0, @family.currency) if amounts.empty?

      amounts.sum(Money.new(0, amounts.first.currency))
    end
end
