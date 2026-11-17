# Fulas Bank: how a cell of the Informe reads on screen (see StatusReport).
module StatusReportsHelper
  def status_report_cell(value, format)
    return "—" if value.nil?

    case format
    when :date then l(value, format: "%d/%m/%Y")
    when :month then l(value, format: "%b %Y")
    when :money then format_money(Money.new(value, Current.family.currency))
    when :percent then number_to_percentage(value, precision: value.to_d.frac.zero? ? 0 : 1)
    when :number then number_with_precision(value, precision: 2, strip_insignificant_zeros: true, delimiter: ".", separator: ",")
    else value.to_s
    end
  end

  def status_report_money(amount)
    format_money(Money.new(amount || 0, Current.family.currency))
  end
end
