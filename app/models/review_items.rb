# Fulas Bank: the «Necesita revisión» bell, after FlowVista: one place for
# what is worth a look —
#   - possible double charges (see DuplicateCharges);
#   - recurring payments whose price went up lately;
#   - recurring payments overdue this month;
#   - payments due in the next few days that are paid by hand.
#
# "Seen" items are remembered in the user's preferences and leave the list
# (a double charge marked seen is the same as "not a duplicate").
class ReviewItems
  PREFERENCE_KEY = "seen_review_items".freeze
  PRICE_DAYS = 45
  DUE_SOON_DAYS = 3

  Item = Data.define(:key, :kind, :title, :date, :amount, :previous_amount)

  attr_reader :family, :user, :today

  def initialize(family, user:, today: Date.current)
    @family = family
    @user = user
    @today = today
  end

  def self.mark_seen!(user, key)
    kind, rest = key.to_s.split(":", 2)
    return if rest.blank?

    if kind == "duplicate"
      DuplicateCharges.dismiss!(user, rest)
    else
      user.with_lock do
        preferences = (user.preferences || {}).deep_dup
        preferences[PREFERENCE_KEY] = (Array(preferences[PREFERENCE_KEY]) | [ key.to_s ]).last(500)
        user.update!(preferences: preferences)
      end
    end
  end

  def items
    @items ||= (duplicates + price_increases + overdue + due_soon).reject { |item| seen.include?(item.key) }
  end

  def count
    items.size
  end

  def any?
    items.any?
  end

  def currency
    family.currency
  end

  private
    def duplicates
      DuplicateCharges.new(family, user: user, today: today).pairs.map do |pair|
        Item.new(key: "duplicate:#{pair.key}", kind: :duplicate, title: pair.name, date: pair.second.date, amount: pair.amount, previous_amount: nil)
      end
    end

    def price_increases
      RecurringPriceChange.where(recurring_transaction_id: family.recurring_transactions.accessible_by(user).active.select(:id))
                          .where(effective_on: (today - PRICE_DAYS)..today)
                          .where("ABS(recurring_price_changes.new_amount) > ABS(recurring_price_changes.previous_amount)")
                          .includes(recurring_transaction: :merchant)
                          .order(effective_on: :desc)
                          .map do |change|
        Item.new(key: "price:#{change.id}", kind: :price_increase, title: change.recurring_transaction.display_name, date: change.effective_on,
                 amount: Money.new(change.new_amount.abs, change.currency), previous_amount: Money.new(change.previous_amount.abs, change.currency))
      end
    end

    def overdue
      this_month.payments.select { |payment| payment.state == :overdue && !payment.income? }.map do |payment|
        Item.new(key: "overdue:#{payment.occurrence.id}", kind: :overdue, title: payment.name, date: payment.date, amount: money(payment.amount), previous_amount: nil)
      end
    end

    def due_soon
      (this_month.payments + next_month.payments)
        .select { |payment| !payment.paid && !payment.income? && !payment.series.autopay? && payment.date.between?(today, today + DUE_SOON_DAYS) }
        .map do |payment|
          Item.new(key: "due:#{payment.occurrence.id}", kind: :due_soon, title: payment.name, date: payment.date, amount: money(payment.amount), previous_amount: nil)
        end
    end

    def this_month
      @this_month ||= MonthPlan.new(family, user: user, month: today, today: today)
    end

    def next_month
      @next_month ||= MonthPlan.new(family, user: user, month: today.next_month, today: today)
    end

    def money(amount)
      Money.new(amount, currency)
    end

    def seen
      @seen ||= Array(user.preferences&.dig(PREFERENCE_KEY)).to_set
    end
end
