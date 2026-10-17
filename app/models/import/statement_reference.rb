# Fulas Bank: the account a bank statement is for, as printed on it. Spanish
# banks print the IBAN in the title rows above the movements, often masked:
# BBVA shows "ES12 0182 **** **** 1234". The reference kept is the bank's code
# (the first four digits after the check digits) and the last four digits,
# "0182-1234": enough to tell the user's accounts apart, and the same whether
# the IBAN is printed whole or masked.
#
# The account an imported statement was for learns its reference once the
# import is published (Import#remember_statement_reference!), so the next
# statement of that account is recognised on its own (Import::AccountGuess).
module Import::StatementReference
  IBAN = /\bES\d{2}[\s.-]?([\d*•xX][\d*•xX\s.-]{6,40})/i
  # Title rows are at the top: no need to read a whole CSV for them.
  CSV_PREAMBLE_LINES = 15

  module_function

  # @param content [String] the file as uploaded (Excel or CSV)
  # @return [String, nil] "0182-1234", or nil without an IBAN
  def from(content)
    match = preamble(content.to_s).match(IBAN)
    return if match.nil?

    chars = match[1].gsub(/[^\d*•xX]/, "")
    bank = chars.first(4)
    tail = chars.scan(/\d/).last(4).join
    return unless bank.match?(/\A\d{4}\z/) && tail.size == 4 && chars.size > 8

    "#{bank}-#{tail}"
  end

  def preamble(content)
    if Import::XlsxConverter.xlsx?(content)
      Import::XlsxConverter.new(content).preamble_text
    else
      content.dup.force_encoding(Encoding::UTF_8).scrub("").lines.first(CSV_PREAMBLE_LINES).join(" | ")
    end
  rescue Import::XlsxConverter::Error
    ""
  end
end
