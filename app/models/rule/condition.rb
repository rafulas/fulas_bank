class Rule::Condition < ApplicationRecord
  SUPPORTED_CONDITION_TYPES = (Rule::Registry::TransactionResource.condition_filter_keys + [ "compound" ]).freeze

  LEGACY_CONDITION_TYPE_ALIASES = {
    "name" => "transaction_name"
  }.freeze

  belongs_to :rule, touch: true, optional: -> { where.not(parent_id: nil) }
  belongs_to :parent, class_name: "Rule::Condition", optional: true, inverse_of: :sub_conditions

  has_many :sub_conditions, -> { order(:created_at, :id) }, class_name: "Rule::Condition", foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent

  before_validation :normalize_legacy_condition_type

  validates :condition_type, presence: true, inclusion: { in: SUPPORTED_CONDITION_TYPES, allow_blank: true }
  validates :operator, presence: true
  validates :value, presence: true, unless: -> { compound? || Rule::ConditionFilter::VALUELESS_OPERATORS.include?(operator) }
  validate :value_is_a_valid_regex, if: -> { operator == "matches" && value.present? }

  accepts_nested_attributes_for :sub_conditions, allow_destroy: true

  # We don't store rule_id on sub_conditions, so "walk up" to the parent rule
  def rule
    parent&.rule || super
  end

  def compound?
    condition_type == "compound"
  end

  def apply(scope)
    if compound?
      build_compound_scope(scope)
    else
      filter.apply(scope, operator, value)
    end
  end

  def prepare(scope)
    if compound?
      sub_conditions.reduce(scope) { |s, sub| sub.prepare(s) }
    else
      filter.prepare(scope)
    end
  end

  def value_display
    if value.present?
      if options
        options.find { |option| option.last == value }&.first
      else
        value
      end
    else
      ""
    end
  end

  # Fulas Bank: the operator as the rule form names it ("Empieza por"), not
  # its stored code ("starts_with"), for the rules list.
  def operator_display
    operators.find { |_label, code| code == operator }&.first&.downcase || operator
  rescue StandardError
    operator
  end

  def options
    filter.options
  end

  def operators
    filter.operators
  end

  def filter
    rule.registry.get_filter!(condition_type)
  rescue Rule::Registry::UnsupportedConditionError
    Rule::ConditionFilter::Unsupported.new(rule, condition_type)
  end

  private
    # Fulas Bank: a "matches" condition needs an expression the database can
    # run. Ruby's syntax is close enough to PostgreSQL's to catch typos.
    def value_is_a_valid_regex
      if value.length > Rule::ConditionFilter::REGEX_MAX_LENGTH
        errors.add(:value, :regex_too_long, count: Rule::ConditionFilter::REGEX_MAX_LENGTH)
      else
        Regexp.new(value, Regexp::IGNORECASE, timeout: 0.1)
      end
    rescue RegexpError
      errors.add(:value, :invalid_regex)
    end

    def normalize_legacy_condition_type
      return if condition_type.blank?

      normalized = LEGACY_CONDITION_TYPE_ALIASES[condition_type]
      self.condition_type = normalized if normalized
    end

    def build_compound_scope(scope)
      if operator == "or"
        combined_scope = sub_conditions
          .map { |sub| sub.apply(scope) }
          .reduce { |acc, s| acc.or(s) }

        combined_scope || scope
      else
        sub_conditions.reduce(scope) { |s, sub| sub.apply(s) }
      end
    end
end
