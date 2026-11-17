require "test_helper"

class StatusReportTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
  end

  test "the copy is tab-separated with a decimal comma, plain dates and no currency" do
    block = StatusReport::Block.new(headers: [ "Cuenta", "Saldo", "Fecha" ],
                                    rows: [ [ "BBVA\tNómina", BigDecimal("8420.155"), Date.new(2026, 11, 17) ], [ "Tarjeta", BigDecimal("-612.8"), nil ],
                                            [ "Ahorro", BigDecimal("21300"), nil ] ],
                                    formats: %i[text money date])

    assert_equal "Cuenta\tSaldo\tFecha\nBBVA Nómina\t8420,16\t17/11/2026\nTarjeta\t-612,80\t\nAhorro\t21300\t", block.to_tsv
    assert_equal "BBVA Nómina\t8420,16\t17/11/2026\nTarjeta\t-612,80\t\nAhorro\t21300\t", block.to_tsv(header: false)
  end

  test "totals split what the chosen accounts hold and owe" do
    depository = accounts(:depository)
    card = accounts(:credit_card)
    loan = accounts(:loan)
    report = StatusReport.new(@family, user: @user, accounts: [ depository, card, loan ])

    totals = report.totals
    assert_equal depository.balance.to_d - card.balance.to_d, totals.liquidity
    assert_equal loan.balance.to_d, totals.debt
    assert_equal depository.balance.to_d - card.balance.to_d - loan.balance.to_d, totals.net_worth
  end

  test "only the chosen accounts and sections go in" do
    report = StatusReport.new(@family, user: @user, accounts: [ accounts(:depository) ], sections: %w[balances bogus])

    assert_equal %w[balances], report.sections
    assert_equal [ accounts(:depository).name ], report.balances.rows.map(&:first)
    assert report.loans.empty?
  end

  test "net worth has a row for the end of each of the last months and today" do
    report = StatusReport.new(@family, user: @user, accounts: [ accounts(:depository) ])
    rows = report.net_worth.rows

    assert_equal StatusReport::HISTORY_MONTHS, rows.size
    assert_equal Date.current, rows.last.first
    assert_equal accounts(:depository).balance.to_d, rows.last.last
  end
end
