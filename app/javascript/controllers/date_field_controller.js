import { Controller } from "@hotwired/stimulus";

// Fulas Bank: a date field with the app's own calendar instead of the
// browser's. The input stays a real date input (the date can still be typed,
// and the form sends it as before); its own picker icon is hidden, and
// clicking it, or the calendar button beside it, opens a month with quick
// choices: today, yesterday and payday. Every StyledFormBuilder#date_field
// gets it (the markup is built there).
export default class extends Controller {
  static targets = ["input", "button"];

  static values = {
    labels: Object,
    monthNames: Array,
    weekdays: Array,
    payday: Number,
    today: String,
  };

  connect() {
    this.input = this.inputTarget;
    this.button = this.buttonTarget;
    this.holder = this.element;
    this.input.addEventListener("click", this.openFromClick);
    document.addEventListener("click", this.outside);
    document.addEventListener("keydown", this.escape);
  }

  disconnect() {
    this.close();
    this.input.removeEventListener("click", this.openFromClick);
    document.removeEventListener("click", this.outside);
    document.removeEventListener("keydown", this.escape);
  }

  // A click on the field (not typing into it) opens the calendar.
  openFromClick = (event) => {
    if (event.detail > 0) this.open();
  };

  toggle = (event) => {
    event.preventDefault();
    this.panel ? this.close() : this.open();
  };

  outside = (event) => {
    if (!this.panel) return;
    if (
      this.panel.contains(event.target) ||
      this.button.contains(event.target) ||
      event.target === this.input
    )
      return;
    this.close();
  };

  escape = (event) => {
    if (event.key === "Escape" && this.panel) this.close();
  };

  open() {
    if (this.panel || this.input.disabled || this.input.readOnly) return;
    const value = this.#parse(this.input.value) || this.#today();
    this.month = new Date(value.getFullYear(), value.getMonth(), 1);

    this.panel = document.createElement("div");
    this.panel.className =
      "absolute left-0 top-full mt-2 z-50 w-80 max-w-[90vw] p-3 rounded-xl bg-container shadow-border-lg space-y-3";
    this.panel.setAttribute("role", "dialog");
    this.holder.appendChild(this.panel);
    this.#draw();
  }

  close() {
    this.panel?.remove();
    this.panel = null;
  }

  #draw() {
    const today = this.#today();
    const chosen = this.#parse(this.input.value);
    const panel = this.panel;
    panel.replaceChildren();

    // Quick choices.
    const quick = document.createElement("div");
    quick.className = "flex flex-wrap gap-1.5";
    const choices = [
      [this.labelsValue.today, today],
      [
        this.labelsValue.yesterday,
        new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1),
      ],
    ];
    if (this.paydayValue) {
      let pay = new Date(
        today.getFullYear(),
        today.getMonth(),
        this.paydayValue,
      );
      if (pay > today)
        pay = new Date(
          today.getFullYear(),
          today.getMonth() - 1,
          this.paydayValue,
        );
      choices.push([this.labelsValue.payday, pay]);
    }
    for (const [label, date] of choices) {
      const chip = document.createElement("button");
      chip.type = "button";
      chip.className = [
        "h-9 px-3 rounded-full border text-sm cursor-pointer",
        this.#same(date, chosen)
          ? "border-current text-brand bg-brand-subtle"
          : "border-secondary text-primary hover:bg-container-hover",
      ].join(" ");
      chip.textContent = label;
      chip.addEventListener("click", () => this.#pick(date));
      quick.appendChild(chip);
    }
    panel.appendChild(quick);

    // Month and arrows.
    const header = document.createElement("div");
    header.className = "flex items-center justify-between";
    const arrow = (label, delta, symbol) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className =
        "size-11 flex items-center justify-center rounded-full bg-container-inset text-lg text-primary cursor-pointer hover:bg-container-inset-hover";
      b.setAttribute("aria-label", label);
      b.textContent = symbol;
      b.addEventListener("click", () => {
        this.month = new Date(
          this.month.getFullYear(),
          this.month.getMonth() + delta,
          1,
        );
        this.#draw();
      });
      return b;
    };
    const title = document.createElement("span");
    title.className =
      "text-sm font-semibold text-primary first-letter:uppercase";
    title.textContent = `${this.monthNamesValue[this.month.getMonth()]} ${this.month.getFullYear()}`;
    header.append(
      arrow(this.labelsValue.prev, -1, "‹"),
      title,
      arrow(this.labelsValue.next, 1, "›"),
    );
    panel.appendChild(header);

    // Weekdays and days, Monday first.
    const grid = document.createElement("div");
    grid.className = "grid grid-cols-7 gap-y-1 text-center";
    for (const day of this.weekdaysValue) {
      const head = document.createElement("span");
      head.className = "text-xs font-medium text-secondary pb-1";
      head.textContent = day;
      head.setAttribute("aria-hidden", "true");
      grid.appendChild(head);
    }
    const lead = (this.month.getDay() + 6) % 7;
    for (let i = 0; i < lead; i++)
      grid.appendChild(document.createElement("span"));
    const days = new Date(
      this.month.getFullYear(),
      this.month.getMonth() + 1,
      0,
    ).getDate();
    for (let d = 1; d <= days; d++) {
      const date = new Date(this.month.getFullYear(), this.month.getMonth(), d);
      const cell = document.createElement("span");
      cell.className = "flex justify-center";
      const b = document.createElement("button");
      b.type = "button";
      const picked = this.#same(date, chosen);
      b.className = [
        "size-10 rounded-full text-sm cursor-pointer",
        picked
          ? "bg-inverse text-inverse font-semibold"
          : "text-primary hover:bg-container-hover",
        !picked && this.#same(date, today)
          ? "ring-1 ring-inset ring-current text-brand font-semibold"
          : "",
      ].join(" ");
      b.textContent = String(d);
      b.setAttribute(
        "aria-label",
        `${d} ${this.monthNamesValue[this.month.getMonth()]} ${this.month.getFullYear()}`,
      );
      b.addEventListener("click", () => this.#pick(date));
      cell.appendChild(b);
      grid.appendChild(cell);
    }
    panel.appendChild(grid);
  }

  #pick(date) {
    this.input.value = this.#iso(date);
    this.input.dispatchEvent(new Event("input", { bubbles: true }));
    this.input.dispatchEvent(new Event("change", { bubbles: true }));
    this.close();
    this.input.focus();
  }

  #today() {
    return this.#parse(this.todayValue) || new Date();
  }

  #same(a, b) {
    return !!a && !!b && this.#iso(a) === this.#iso(b);
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
