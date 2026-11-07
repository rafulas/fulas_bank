# Fulas Bank: what is coming up in Vencimientos y garantías, for Inicio and
# the top of the page — the deadlines within their reminder window (or
# already past) and the insurance policies about to renew, soonest first.
class Deadline::Upcoming
  Item = Data.define(:name, :date, :icon, :record) do
    def insurance?
      record.is_a?(Insurance)
    end

    def overdue?(today)
      date < today
    end

    def days_left(today)
      (date - today).to_i
    end
  end

  attr_reader :family, :today

  def initialize(family, today: Date.current)
    @family = family
    @today = today
  end

  def items
    @items ||= (deadline_items + insurance_items).sort_by { |item| [ item.date, item.name ] }
  end

  def any?
    items.any?
  end

  private
    def deadline_items
      family.deadlines.pending.where(due_on: ..(today + Deadline::REMIND_DAYS.max.days)).includes(:account)
            .select { |deadline| deadline.due_soon?(today) }
            .map { |deadline| Item.new(name: deadline.name, date: deadline.due_on, icon: deadline.icon, record: deadline) }
    end

    def insurance_items
      family.insurances.active.select { |insurance| insurance.renews_soon?(today) }.map do |insurance|
        Item.new(name: insurance.name, date: insurance.next_renewal(today), icon: "shield", record: insurance)
      end
    end
end
