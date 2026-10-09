import { Controller } from "@hotwired/stimulus";

// Reloads the "Bank charge" options of a vehicle log (or property expense)
// form whenever its date
// or amounts change, so the suggested charges are the ones around the date
// and amount being entered rather than those of the day the form was opened.
export default class extends Controller {
  static targets = ["select"];
  // `scope` is the form's parameter prefix: vehicle_log or property_expense.
  static values = {
    url: String,
    scope: { type: String, default: "vehicle_log" },
  };

  refresh(event) {
    if (event.target === this.selectTarget) return;

    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.load(), 250);
  }

  disconnect() {
    clearTimeout(this.timer);
  }

  async load() {
    const url = new URL(this.urlValue, window.location.origin);
    url.searchParams.set("date", this.field("date"));
    url.searchParams.set("amount", this.amount());
    url.searchParams.set("selected", this.selectTarget.value);

    const response = await fetch(url, { headers: { Accept: "text/html" } });
    if (!response.ok) return;

    this.selectTarget.innerHTML = await response.text();
  }

  // The total, or litres times price on a refuel where only those are given.
  amount() {
    const total = this.number("amount");
    if (total > 0) return String(total);

    const product = this.number("quantity") * this.number("unit_price");
    return product > 0 ? product.toFixed(2) : "";
  }

  number(name) {
    const value = Number.parseFloat(this.field(name).replace(",", "."));
    return Number.isFinite(value) ? value : 0;
  }

  field(name) {
    const input = this.element.querySelector(
      `[name="${this.scopeValue}[${name}]"]`,
    );
    return input ? input.value : "";
  }
}
