import { Controller } from "@hotwired/stimulus";

// Fulas Bank: the period picker, after Bilance. Quick choices first (all
// time, a month, a year, a shortcut), each applied at once; "Rango
// personalizado" opens a vertical calendar where the first and the last day
// are tapped, or typed. It fills two inputs (start and end, ISO dates; both
// empty for all time) and submits their form.
//
// Markup: shared/_period_picker.html.erb. The calendar is drawn here, as it
// depends on the dates chosen.
export default class extends Controller {
  static targets = [
    "startInput",
    "endInput",
    "allInput",
    "quick",
    "calendar",
    "monthRow",
    "year",
    "months",
    "rangeLabel",
    "apply",
    "startField",
    "endField",
    "choice",
  ];

  static values = {
    start: String,
    end: String,
    today: String,
    monthNames: Array,
    monthShort: Array,
    payday: Number,
    pickFirst: String,
    pickLast: String,
    submit: { type: Boolean, default: true },
  };

  connect() {
    this.today = this.#parse(this.todayValue) || new Date();
    this.selStart = this.#parse(this.startValue);
    this.selEnd = this.#parse(this.endValue);
    const anchor = this.selEnd || this.selStart || this.today;
    this.windowEnd = new Date(anchor.getFullYear(), anchor.getMonth(), 1);
    this.year = anchor.getFullYear();
    this.#drawMonthRow();
    this.#drawYear();
    this.#markChoices();
  }

  // ---- Quick choices ----

  all() {
    this.#commit(null, null);
  }

  prevMonths() {
    this.windowEnd = new Date(
      this.windowEnd.getFullYear(),
      this.windowEnd.getMonth() - 1,
      1,
    );
    this.#drawMonthRow();
  }

  nextMonths() {
    this.windowEnd = new Date(
      this.windowEnd.getFullYear(),
      this.windowEnd.getMonth() + 1,
      1,
    );
    this.#drawMonthRow();
  }

  pickMonth(event) {
    const [year, month] = event.currentTarget.dataset.month
      .split("-")
      .map(Number);
    this.#commit(new Date(year, month, 1), new Date(year, month + 1, 0));
  }

  prevYear() {
    this.year -= 1;
    this.#drawYear();
  }

  nextYear() {
    this.year += 1;
    this.#drawYear();
  }

  pickYear() {
    this.#commit(new Date(this.year, 0, 1), new Date(this.year, 11, 31));
  }

  shortcut(event) {
    const today = this.today;
    const day = (offset) =>
      new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset);

    switch (event.currentTarget.dataset.period) {
      case "last30":
        return this.#commit(day(-29), today);
      case "last90":
        return this.#commit(day(-89), today);
      case "ytd":
        return this.#commit(new Date(today.getFullYear(), 0, 1), today);
      case "payday": {
        // From the last payday to the day before the next one.
        const pay = this.paydayValue;
        let start = new Date(today.getFullYear(), today.getMonth(), pay);
        if (start > today)
          start = new Date(today.getFullYear(), today.getMonth() - 1, pay);
        const end = new Date(
          start.getFullYear(),
          start.getMonth() + 1,
          pay - 1,
        );
        return this.#commit(start, end);
      }
    }
  }

  // ---- Custom range ----

  openRange() {
    this.quickTarget.hidden = true;
    this.calendarTarget.hidden = false;
    this.#drawCalendar();
    this.#paint();

    const focus = this.selStart || this.today;
    const month = this.monthsTarget.querySelector(
      `[data-month-block="${this.#monthKey(focus)}"]`,
    );
    if (month)
      this.monthsTarget.scrollTop =
        month.offsetTop - this.monthsTarget.offsetTop;
  }

  closeRange() {
    this.calendarTarget.hidden = true;
    this.quickTarget.hidden = false;
  }

  pickDay(event) {
    const date = this.#parse(event.currentTarget.dataset.date);
    if (!this.selStart || this.selEnd) {
      this.selStart = date;
      this.selEnd = null;
    } else if (date < this.selStart) {
      this.selEnd = this.selStart;
      this.selStart = date;
    } else {
      this.selEnd = date;
    }
    this.#paint();
  }

  // The dates can be typed too: the calendar follows them.
  typed() {
    this.selStart = this.#parse(this.startFieldTarget.value);
    this.selEnd = this.#parse(this.endFieldTarget.value);
    if (this.selStart && this.selEnd && this.selEnd < this.selStart) {
      [this.selStart, this.selEnd] = [this.selEnd, this.selStart];
    }
    this.#paint();
  }

  clear() {
    this.selStart = null;
    this.selEnd = null;
    this.#paint();
  }

  applyRange() {
    if (!this.selStart) return;
    this.#commit(this.selStart, this.selEnd || this.selStart);
  }

  // ---- Drawing ----

  #drawMonthRow() {
    const buttons = [];
    for (let back = 3; back >= 0; back--) {
      const month = new Date(
        this.windowEnd.getFullYear(),
        this.windowEnd.getMonth() - back,
        1,
      );
      const label = this.#short(month);
      const button = document.createElement("button");
      button.type = "button";
      button.dataset.action = "period-picker#pickMonth";
      button.dataset.month = `${month.getFullYear()}-${month.getMonth()}`;
      button.className = this.#pillClass(this.#isWholeMonth(month));
      button.textContent =
        month.getFullYear() === this.today.getFullYear()
          ? label
          : `${label} ${String(month.getFullYear()).slice(2)}`;
      button.setAttribute(
        "aria-label",
        `${this.monthNamesValue[month.getMonth()]} ${month.getFullYear()}`,
      );
      buttons.push(button);
    }
    this.monthRowTarget.replaceChildren(...buttons);
  }

  #drawYear() {
    this.yearTarget.textContent = String(this.year);
    const whole =
      this.selStart &&
      this.selEnd &&
      this.#iso(this.selStart) === `${this.year}-01-01` &&
      this.#iso(this.selEnd) === `${this.year}-12-31`;
    this.yearTarget.className = `${this.#pillClass(whole)} grow font-semibold`;
  }

  // The choice buttons rendered on the server (all time, the shortcuts)
  // show which one is chosen.
  #markChoices() {
    for (const button of this.choiceTargets) {
      const active =
        button.dataset.choice === "all"
          ? !this.selStart && !this.selEnd
          : false;
      button.classList.toggle("bg-inverse", active);
      button.classList.toggle("text-inverse", active);
    }
  }

  // Twelve months back and three ahead of the chosen start (or today).
  #drawCalendar() {
    if (this.calendarDrawn) return;
    this.calendarDrawn = true;

    const anchor = this.selStart || this.today;
    const blocks = [];
    for (let offset = -12; offset <= 3; offset++) {
      const month = new Date(
        anchor.getFullYear(),
        anchor.getMonth() + offset,
        1,
      );
      blocks.push(this.#monthBlock(month));
    }
    this.monthsTarget.replaceChildren(...blocks);
  }

  #monthBlock(month) {
    const block = document.createElement("div");
    block.className = "pt-3 space-y-1.5";
    block.dataset.monthBlock = this.#monthKey(month);

    const title = document.createElement("p");
    title.className =
      "text-sm font-semibold text-primary first-letter:uppercase";
    title.textContent = `${this.monthNamesValue[month.getMonth()]} ${month.getFullYear()}`;
    block.appendChild(title);

    const grid = document.createElement("div");
    grid.className = "grid grid-cols-7 gap-y-1";
    const lead = (month.getDay() + 6) % 7;
    for (let i = 0; i < lead; i++)
      grid.appendChild(document.createElement("span"));

    const days = new Date(
      month.getFullYear(),
      month.getMonth() + 1,
      0,
    ).getDate();
    for (let d = 1; d <= days; d++) {
      const date = new Date(month.getFullYear(), month.getMonth(), d);
      const cell = document.createElement("span");
      cell.className = "flex justify-center";
      cell.dataset.cell = this.#iso(date);

      const button = document.createElement("button");
      button.type = "button";
      button.dataset.action = "period-picker#pickDay";
      button.dataset.date = this.#iso(date);
      button.textContent = String(d);
      button.setAttribute(
        "aria-label",
        `${d} ${this.monthNamesValue[month.getMonth()]} ${month.getFullYear()}`,
      );
      cell.appendChild(button);
      grid.appendChild(cell);
    }
    block.appendChild(grid);
    return block;
  }

  // Highlights the chosen days and the band between them, and fills the
  // typed fields and the label.
  #paint() {
    const start = this.selStart ? this.#iso(this.selStart) : null;
    const end = this.selEnd ? this.#iso(this.selEnd) : null;
    const today = this.#iso(this.today);

    for (const cell of this.monthsTarget.querySelectorAll("[data-cell]")) {
      const date = cell.dataset.cell;
      const edge = date === start || date === end;
      const inside = start && end && date > start && date < end;
      const band = start && end && start !== end && (inside || edge);

      cell.className = [
        "flex justify-center",
        band ? "bg-brand-subtle" : "",
        band && date === start ? "rounded-l-full" : "",
        band && date === end ? "rounded-r-full" : "",
      ].join(" ");

      const button = cell.firstElementChild;
      button.className = [
        "size-11 rounded-full text-sm cursor-pointer",
        edge
          ? "bg-inverse text-inverse font-semibold"
          : "text-primary hover:bg-container-hover",
        !edge && date === today
          ? "ring-1 ring-inset ring-current text-brand font-semibold"
          : "",
      ].join(" ");
      button.setAttribute("aria-pressed", edge ? "true" : "false");
    }

    this.startFieldTarget.value = start || "";
    this.endFieldTarget.value = end || "";
    this.applyTarget.disabled = !start;

    if (!start) this.rangeLabelTarget.textContent = this.pickFirstValue;
    else if (!end)
      this.rangeLabelTarget.textContent = `${this.#long(this.selStart)} – ${this.pickLastValue}`;
    else
      this.rangeLabelTarget.textContent = `${this.#long(this.selStart)} – ${this.#long(this.selEnd)}`;
  }

  // ---- Helpers ----

  #commit(start, end) {
    this.startInputTarget.value = start ? this.#iso(start) : "";
    this.endInputTarget.value = end ? this.#iso(end) : "";
    // All time, where empty dates would mean the page's default period.
    if (this.hasAllInputTarget) {
      this.allInputTarget.disabled = !!start;
      this.startInputTarget.disabled = !start;
      this.endInputTarget.disabled = !start;
    }
    this.dispatch("change", {
      detail: {
        start: this.startInputTarget.value,
        end: this.endInputTarget.value,
      },
    });
    if (this.submitValue) this.element.closest("form")?.requestSubmit();
  }

  #isWholeMonth(month) {
    if (!this.selStart || !this.selEnd) return false;
    const last = new Date(month.getFullYear(), month.getMonth() + 1, 0);
    return (
      this.#iso(this.selStart) === this.#iso(month) &&
      this.#iso(this.selEnd) === this.#iso(last)
    );
  }

  #pillClass(active) {
    return [
      "h-11 rounded-lg text-sm font-medium cursor-pointer",
      active
        ? "bg-inverse text-inverse"
        : "text-primary hover:bg-container-hover",
    ].join(" ");
  }

  #short(date) {
    const name = this.monthShortValue[date.getMonth()] || "";
    return name.charAt(0).toUpperCase() + name.slice(1);
  }

  #long(date) {
    return `${date.getDate()} ${this.monthShortValue[date.getMonth()]} ${date.getFullYear()}`;
  }

  #monthKey(date) {
    return `${date.getFullYear()}-${date.getMonth()}`;
  }

  #iso(date) {
    const pad = (n) => String(n).padStart(2, "0");
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  }

  #parse(value) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || "");
    return match
      ? new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
      : null;
  }
}
