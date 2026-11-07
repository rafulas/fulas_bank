# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Quick Entries', type: :request do
  let(:family) do
    Family.create!(
      name: 'API Family',
      currency: 'EUR',
      locale: 'es',
      date_format: '%d-%m-%Y'
    )
  end

  let(:user) do
    family.users.create!(
      email: 'api-user@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: 'API Docs Key',
      key: key,
      scopes: %w[read_write],
      source: 'web'
    )
  end

  let(:'X-Api-Key') { api_key.plain_key }

  let!(:account) do
    Account.create!(
      family: family,
      owner: user,
      name: 'BBVA',
      balance: 1000,
      currency: 'EUR',
      accountable: Depository.create!
    )
  end

  path '/api/v1/quick_entries' do
    post 'Record a movement from plain words' do
      tags 'Quick entries'
      description 'The "apunte exprés" for iOS Shortcuts and Siri. The first number is the amount ' \
                  '(Spanish "1.250,50" or plain "12.5"); a leading "+" or an income word makes it income. ' \
                  'A word naming one cash or card account picks it; the rest is the name, and the latest ' \
                  'movement with that name lends its category and merchant.'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          text: { type: :string, description: 'The movement in plain words, e.g. "12 café" or "+1.250 nómina" (required)' },
          account_id: { type: :string, format: :uuid, description: 'Account to record it in; guessed when omitted' },
          date: { type: :string, format: :date, description: 'Date of the movement; today when omitted' }
        },
        required: %w[text]
      }

      let(:body) { { text: '12 café', account_id: account.id } }

      response '201', 'movement recorded' do
        schema type: :object,
               required: %w[id entry_id name date amount signed_amount currency nature account message],
               properties: {
                 id: { type: :string, format: :uuid, description: 'Transaction ID' },
                 entry_id: { type: :string, format: :uuid },
                 name: { type: :string },
                 date: { type: :string, format: :date },
                 amount: { type: :string, description: 'Formatted absolute amount' },
                 signed_amount: { type: :string, description: 'Positive for expenses, negative for income' },
                 currency: { type: :string },
                 nature: { type: :string, enum: %w[expense income] },
                 account: {
                   type: :object,
                   properties: { id: { type: :string, format: :uuid }, name: { type: :string } }
                 },
                 category: {
                   type: :object,
                   nullable: true,
                   properties: { id: { type: :string, format: :uuid }, name: { type: :string } }
                 },
                 message: { type: :string, description: 'One line to show or speak back' }
               }

        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:'X-Api-Key') { nil }

        run_test!
      end

      response '422', 'no amount in the text' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { text: 'café' } }

        run_test!
      end
    end
  end
end
