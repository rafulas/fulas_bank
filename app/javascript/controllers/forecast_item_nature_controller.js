import { Controller } from "@hotwired/stimulus";

// Fulas Bank: a planned transfer needs the account it goes to, and the
// "Cuenta" field becomes the one it leaves. Hidden and disabled otherwise,
// so an expense or income never sends a destination.
export default class extends Controller {
  static targets = ["nature", "destination", "accountLabel"];

  static values = {
    accountLabel: String,
    fromLabel: String,
  };

  connect() {
    this.refresh();
  }

  refresh() {
    const transfer = this.natureTarget.value === "transfer";

    this.destinationTargets.forEach((field) => {
      field.classList.toggle("hidden", !transfer);
      field.querySelectorAll("select").forEach((select) => {
        select.disabled = !transfer;
      });
    });

    const label = transfer ? this.fromLabelValue : this.accountLabelValue;
    if (this.hasAccountLabelTarget && label) {
      const el = this.accountLabelTarget.querySelector(".form-field__label");
      const wording =
        el &&
        [...el.childNodes].find(
          (node) => node.nodeType === Node.TEXT_NODE && node.textContent.trim(),
        );
      if (wording) wording.textContent = label;
    }
  }
}
