import { Controller } from "@hotwired/stimulus";

// Fulas Bank: the instalments of an insurance paid in custom instalments.
// Shows them (and hides the single "amount of each payment") when the
// frequency is "custom", adds and removes rows, and fills N rows of the same
// amount every so many days from the start date.
export default class extends Controller {
  static targets = [
    "frequency",
    "premium",
    "custom",
    "startDate",
    "count",
    "every",
    "amount",
    "list",
    "template",
    "row",
    "fillError",
  ];

  connect() {
    this.toggle();
  }

  toggle() {
    if (!this.hasFrequencyTarget) return;

    const custom = this.frequencyTarget.value === "custom";
    this.customTarget.classList.toggle("hidden", !custom);
    if (this.hasPremiumTarget)
      this.premiumTarget.classList.toggle("hidden", custom);
    if (custom && this.rowTargets.length === 0) this.add();
  }

  add(event) {
    event?.preventDefault();
    this.listTarget.append(this.templateTarget.content.cloneNode(true));
  }

  remove(event) {
    event.preventDefault();
    event.currentTarget
      .closest("[data-insurance-installments-target='row']")
      ?.remove();
  }

  fill(event) {
    event.preventDefault();

    const count = Number.parseInt(this.countTarget.value, 10);
    const every = Number.parseInt(this.everyTarget.value, 10);
    const start = this.hasStartDateTarget ? this.startDateTarget.value : "";
    const valid = start && count > 0 && count <= 24 && every > 0;

    this.fillErrorTarget.classList.toggle("hidden", Boolean(valid));
    if (!valid) return;

    this.listTarget.innerHTML = "";
    const [year, month, day] = start.split("-").map(Number);

    for (let index = 0; index < count; index++) {
      const date = new Date(year, month - 1, day + index * every);
      this.add();
      const row = this.rowTargets[this.rowTargets.length - 1];
      row.querySelector("input[type='date']").value = this.isoDate(date);
      row.querySelector("input[type='number']").value = this.amountTarget.value;
    }
  }

  isoDate(date) {
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${date.getFullYear()}-${month}-${day}`;
  }
}
