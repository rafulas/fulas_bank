# Fulas Bank: the "apunte exprés". A movement written the way one would say
# it ("12 café", "+1.250 nómina", "35,90 gasolina tarjeta"), typically from
# an iOS Shortcut or Siri, turned into a real transaction:
#
# - the first number is the amount, Spanish style ("1.250,50") or plain
#   ("12.5"); a leading "+" or an income word marks it as income, otherwise
#   it is an expense;
# - a word that names one of the user's accounts ("bbva", "tarjeta") picks
#   that account; otherwise the default account for movements, and failing
#   that the most recently used one (cash and card accounts only);
# - the rest is the name, and the latest movement with the same name lends
#   its category and merchant, so "café" lands where the last café did.
class QuickEntry
  include ActiveModel::Validations

  # Words that only say which way the money goes, dropped from the name.
  INCOME_WORDS = %w[ingreso ingresos cobro cobre cobrado income].freeze
  EXPENSE_WORDS = %w[gasto gastos pago pague pagado expense].freeze
  # Words that also mean income but are a fine name ("Nómina").
  INCOME_NAMES = %w[nomina sueldo salario].freeze
  MIN_ACCOUNT_WORD_LENGTH = 3
  AMOUNT_PATTERN = /(?<sign>[+-])?\s*(?<number>\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d+(?:[.,]\d{1,2})?)\s*(?:€|eur(?:os?)?\b)?/i

  attr_reader :user, :text, :date, :entry

  validates :text, presence: true
  validate :amount_present
  validate :account_present

  def initialize(user:, text:, date: nil, account_id: nil)
    @user = user
    @text = text.to_s.squish
    @date = date.presence || Date.current
    @account_id = account_id.presence
  end

  def save
    return false unless valid?

    @entry = account.entries.new(
      name: name,
      date: date,
      amount: signed_amount,
      currency: account.currency,
      entryable: Transaction.new(category_id: precedent&.transaction&.category_id,
                                 merchant_id: precedent&.transaction&.merchant_id)
    )

    if @entry.save
      @entry.sync_account_later
      @entry.lock_saved_attributes!
      @entry.mark_user_modified!
      true
    else
      @entry.errors.full_messages.each { |message| errors.add(:base, message) }
      false
    end
  end

  # One line to show or speak back once saved, e.g.
  # "Gasto apuntado: 12,00 € · Café · BBVA (Cafeterías)".
  def summary
    return unless entry&.persisted?

    category = entry.transaction.category&.name
    I18n.t(income? ? "quick_entries.summary.income" : "quick_entries.summary.expense",
           amount: entry.amount_money.abs.format,
           name: entry.name,
           account: entry.account.name) + (category ? " (#{category})" : "")
  end

  def income?
    amount_match&.[](:sign) == "+" || (words & (INCOME_WORDS + INCOME_NAMES)).any?
  end

  def amount
    return unless amount_match

    number = amount_match[:number]
    number = number.delete(".").tr(",", ".") if number.match?(/\.\d{3}(?:\D|\z)/) || number.include?(",")
    BigDecimal(number)
  end

  def account
    return @account if defined?(@account)

    @account = if @account_id
      explicit_account
    else
      named_account || user.default_account_for_transactions || last_used_account
    end
  end

  def name
    remaining = description_words
    return I18n.t(income? ? "quick_entries.default_name.income" : "quick_entries.default_name.expense") if remaining.empty?

    remaining.join(" ").upcase_first
  end

  private
    def signed_amount
      income? ? -amount.abs : amount.abs
    end

    def amount_match
      return @amount_match if defined?(@amount_match)

      @amount_match = AMOUNT_PATTERN.match(text)
    end

    def text_without_amount
      amount_match ? text.sub(amount_match[0], " ").squish : text
    end

    # Original words (accents kept) without the amount and the words that
    # only mark the nature or name the account.
    def description_words
      text_without_amount.split.reject do |word|
        key = normalize(word)
        key.in?(INCOME_WORDS) || key.in?(EXPENSE_WORDS) || key == account_word
      end
    end

    def words
      @words ||= text_without_amount.split.map { |word| normalize(word) }
    end

    def normalize(word)
      I18n.transliterate(word.to_s.downcase).gsub(/[^a-z0-9]/, "")
    end

    def writable_accounts
      @writable_accounts ||= user.family.accounts.writable_by(user).visible.manual.to_a
    end

    # Only cash and card accounts can be guessed: "35 gasolina coche" must
    # not land in a vehicle asset called "Coche".
    def spending_accounts
      @spending_accounts ||= writable_accounts.select { |candidate| candidate.accountable_type.in?(Account::MOVABLE_TRANSACTION_TYPES) }
    end

    def explicit_account
      return unless @account_id

      writable_accounts.find { |candidate| candidate.id.to_s == @account_id.to_s }
    end

    def named_account
      match = words.lazy.filter_map do |word|
        next if word.length < MIN_ACCOUNT_WORD_LENGTH

        found = spending_accounts.select { |candidate| account_words(candidate).include?(word) }
        [ word, found.first ] if found.one?
      end.first

      @account_word = match&.first
      match&.last
    end

    def account_word
      account
      @account_word
    end

    def account_words(account)
      account.name.to_s.split(/[\s\-_\/·.,]+/).map { |word| normalize(word) }
    end

    def last_used_account
      Account.in_picker_order(spending_accounts.select(&:active?)).first
    end

    # The latest movement with the same name and the same nature, falling
    # back to one whose name contains it.
    def precedent
      return @precedent if defined?(@precedent)
      return @precedent = nil if description_words.empty?

      query = description_words.join(" ").downcase
      scope = user.family.entries
                  .joins(:account).merge(Account.accessible_by(user))
                  .where(entryable_type: "Transaction")
                  .where(income? ? "entries.amount < 0" : "entries.amount > 0")
                  .includes(:entryable)
                  .order(date: :desc, created_at: :desc)

      @precedent = scope.where("LOWER(entries.name) = ?", query).first ||
                   scope.where("entries.name ILIKE ?", "%#{Entry.sanitize_sql_like(query)}%").first
    end

    def amount_present
      errors.add(:base, I18n.t("quick_entries.errors.amount_missing")) if amount.nil? || amount.zero?
    end

    def account_present
      errors.add(:base, I18n.t("quick_entries.errors.account_missing")) if account.nil?
    end
end
