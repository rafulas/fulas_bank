# Fulas Bank: the movements panel's 90-day balance chart, loaded when
# «Análisis» is opened (see transactions/_panel): worked out with every
# page of the list, it was there for a section that is usually closed.
class Transactions::PanelBalancesController < ApplicationController
  def show
    @series = Transaction::Panel.new(Current.family, user: Current.user).balance_series
  end
end
