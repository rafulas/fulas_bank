import { Controller } from "@hotwired/stimulus";

// Fulas Bank: a date field with the app's own calendar instead of the
// browser's. The input stays a real date input (the date can still be typed,
// and the form sends it as before); its own picker icon is hidden, and
// clicking it, or the calendar button beside it, opens a month with quick
// choices: today, yesterday and payday. Every StyledFormBuilder#date_field
// gets it (the markup is built there).
//
// The calendar is shown in the browser's top layer (a popover) and placed
// beside the field with fixed coordinates, so a dialog that scrolls or clips
// its content cannot cut it, and it opens upwards when there is no room
// below.
export default class extends Controller {
  static targets = ["input", "button"];

  static values = {
    labels: Object,
    monthNames: Array,
    weekdays: Array,
    payday: Number,
    today: String,
  };

  static GAP = 8;

  connect() {
    this.input = this.inputTarget;
    this.button = this.buttonTarget;
    this.holder = this.element;
    // (A page restored from Turbo's cache keeps the lock set below.)
    this.lockedByPage =
      this.input.readOnly && this.input.dataset.safariLock !== "true";
    // Safari opens its own calendar whenever the field takes the focus from a
    // click or a tap, whatever the page does, so both calendars appeared.
    // There the field is read-only (it is still sent with the form) and the
    // date is chosen in this calendar.
    this.safari = this.constructor.isSafari();
    if (this.safari && !this.lockedByPage) {
      this.input.readOnly = true;
      this.input.dataset.safariLock = "true";
    }
    this.input.addEventListener("mousedown", this.openFromPointer);
    document.addEventListener("click", this.outside);
    document.addEventListener("keydown", this.escape);
  }

  disconnect() {
    this.close();
    this.input.removeEventListener("mousedown", this.openFromPointer);
    document.removeEventListener("click", this.outside);
    document.removeEventListener("keydown", this.escape);
  }

  // A click on the field opens this calendar and not the browser's own. The
  // field still gets the focus, so the date can be typed (not in Safari, see
  // connect).
  openFromPointer = (event) => {
    if (event.button !== 0 || this.unavailable()) return;
    event.preventDefault();
    if (!this.safari) this.input.focus({ preventScroll: true });
    // The click that follows this press must not close the calendar it
    // opens: if the calendar covers the field, the click lands on whatever
    // holds them both, which counts as outside.
    this.pressedField = true;
    this.panel ? this.close() : this.open();
  };

  static isSafari() {
    const agent = navigator.userAgent;
    return (
      /Safari\//.test(agent) &&
      !/Chrome|Chromium|CriOS|FxiOS|Edg|Android/.test(agent)
    );
  }

  // Disabled, or read-only by the page itself (not by the Safari lock).
  unavailable() {
    return this.input.disabled || this.lockedByPage;
  }

  toggle = (event) => {
    event.preventDefault();
    this.panel ? this.close() : this.open();
  };

  // The path is taken when the click starts: a month arrow is replaced while
  // the calendar redraws, and by the time this runs it is no longer inside
  // the calendar, which used to close it.
  outside = (event) => {
    if (this.pressedField) {
      this.pressedField = false;
      return;
    }
    if (!this.panel) return;
    const path = event.composedPath();
    if (
      path.includes(this.panel) ||
      path.includes(this.button) ||
      path.includes(this.input)
    )
      return;
    this.close();
  };

  escape = (event) => {
    if (event.key === "Escape" && this.panel) this.close();
  };

  reposition = () => {
    if (this.panel) this.#place();
  };

  open() {
    if (this.panel || this.unavailable()) return;
    const value = this.#parse(this.input.value) || this.#today();
    this.month = new Date(value.getFullYear(), value.getMonth(), 1);

    this.panel = document.createElement("div");
    this.panel.className =
      "fixed z-50 w-80 max-w-[calc(100vw-1rem)] p-3 m-0 border-0 rounded-xl bg-container text-primary shadow-border-lg space-y-3";
    this.panel.setAttribute("role", "dialog");
    this.panel.style.inset = "auto";
    // A Turbo page refresh (morph) would remove the open calendar, which is
    // not in the server's HTML: keep it until it is closed.
    this.panel.addEventListener("turbo:before-morph-element", (event) =>
      event.preventDefault(),
    );
    const popover = typeof this.panel.showPopover === "function";
    if (popover) this.panel.setAttribute("popover", "manual");
    this.holder.appendChild(this.panel);
    if (popover) this.panel.showPopover();
    this.#draw();

    window.addEventListener("scroll", this.reposition, true);
    window.addEventListener("resize", this.reposition);
  }

  close() {
    window.removeEventListener("scroll", this.reposition, true);
    window.removeEventListener("resize", this.reposition);
    this.panel?.remove();
    this.panel = null;
  }

  // Below the field, or above it when it does not fit below; always whole
  // inside the window, so nothing has to scroll to reach it.
  #place() {
    const gap = this.constructor.GAP;
    const field = this.holder.getBoundingClientRect();
    const width = this.panel.offsetWidth;
    const height = this.panel.offsetHeight;

    let top = field.bottom + gap;
    if (top + height > window.innerHeight - gap) {
      // Above the field when it fits there; otherwise as low as it can go
      // while staying whole in the window.
      top =
        field.top - gap - height >= gap
          ? field.top - gap - height
          : window.innerHeight - gap - height;
    }
    const left = Math.min(
      Math.max(field.left, gap),
      Math.max(window.innerWidth - width - gap, gap),
    );

    this.panel.style.top = `${Math.max(top, gap)}px`;
    this.panel.style.left = `${left}px`;
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
    this.#place();
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
