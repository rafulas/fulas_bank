# Fulas Bank: the days banks in Madrid do not work, to move a card's charge
# to the previous working day and a purchase made on a holiday to the next.
#
# National holidays plus those of the Comunidad and the city of Madrid that
# fall on the same date every year (Jueves Santo, 2 May, San Isidro and the
# Almudena). Holidays some years move to the Monday after, or that the
# Comunidad picks year by year, are not included: a day off by mistake only
# moves an expected date by one day.
module SpanishHolidays
  FIXED = [
    [ 1, 1 ],   # Año Nuevo
    [ 1, 6 ],   # Reyes
    [ 5, 1 ],   # Fiesta del Trabajo
    [ 5, 2 ],   # Comunidad de Madrid
    [ 5, 15 ],  # San Isidro (Madrid)
    [ 8, 15 ],  # Asunción
    [ 10, 12 ], # Fiesta Nacional
    [ 11, 1 ],  # Todos los Santos
    [ 11, 9 ],  # Almudena (Madrid)
    [ 12, 6 ],  # Constitución
    [ 12, 8 ],  # Inmaculada
    [ 12, 25 ]  # Navidad
  ].freeze

  module_function

  def holiday?(date)
    FIXED.include?([ date.month, date.day ]) || easter_holidays(date.year).include?(date)
  end

  def business_day?(date)
    !date.saturday? && !date.sunday? && !holiday?(date)
  end

  # The date itself when it is a working day, or the working day before it.
  def previous_business_day(date)
    date -= 1 until business_day?(date)
    date
  end

  # The date itself when it is a working day, or the working day after it.
  def next_business_day(date)
    date += 1 until business_day?(date)
    date
  end

  # `count` working days after the date (0: the date itself if it is one).
  def add_business_days(date, count)
    date = next_business_day(date)
    count.times { date = next_business_day(date + 1) }
    date
  end

  # Jueves Santo (Madrid) and Viernes Santo (national).
  def easter_holidays(year)
    easter = easter_sunday(year)
    [ easter - 3, easter - 2 ]
  end

  # Easter Sunday in the Gregorian calendar (the "anonymous" algorithm).
  def easter_sunday(year)
    a = year % 19
    b, c = year.divmod(100)
    d, e = b.divmod(4)
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c.divmod(4)
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) / 451
    month, day = (h + l - 7 * m + 114).divmod(31)
    Date.new(year, month, day + 1)
  end
end
