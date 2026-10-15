import { Controller } from "@hotwired/stimulus";

// The budget editor of Planes. A main category can be broken down into its
// subcategories: once any of them has an amount, the main category's amount
// is their sum and cannot be typed. The "suggest" button fills every empty
// main category with what is usually spent there (its data-suggested value).
export default class extends Controller {
  static targets = ["group", "main", "sub", "total"];

  connect() {
    this.refresh();
  }

  refresh() {
    let total = 0;

    this.groupTargets.forEach((group) => {
      const main = this.mainTargets.find((input) => group.contains(input));
      const subs = this.subTargets.filter((input) => group.contains(input));
      const subTotal = subs.reduce((sum, input) => sum + this.value(input), 0);
      const brokenDown = subs.some((input) => this.value(input) > 0);

      if (main) {
        main.readOnly = brokenDown;
        if (brokenDown) main.value = this.format(subTotal);
        total += this.value(main);
      }
    });

    if (this.hasTotalTarget) {
      this.totalTarget.textContent = new Intl.NumberFormat(document.documentElement.lang || "es", {
        maximumFractionDigits: 0,
      }).format(total);
    }
  }

  suggest() {
    this.mainTargets.forEach((input) => {
      const suggested = input.dataset.suggested;
      if (suggested && !input.readOnly && this.value(input) === 0) input.value = suggested;
    });
    this.refresh();
  }

  value(input) {
    const number = Number.parseFloat(String(input.value).replace(",", "."));
    return Number.isFinite(number) && number > 0 ? number : 0;
  }

  format(number) {
    return (Math.round(number * 100) / 100).toString();
  }
}
