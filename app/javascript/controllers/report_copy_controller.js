import { Controller } from "@hotwired/stimulus";

const STATUS_DELAY_MS = 4000;

// Fulas Bank: «Copiar para Sheets» in the Informe. Copies a block's
// tab-separated text so a spreadsheet pastes one value per cell. The
// clipboard API only works over HTTPS or localhost; over plain http (the
// server reached through Tailscale) it falls back to a hidden selection.
export default class extends Controller {
  static targets = ["source", "status"];
  static values = { copied: String, failed: String };

  async copy(event) {
    event.preventDefault();
    const copied = await this.#write(this.sourceTarget.value);
    this.#announce(copied ? this.copiedValue : this.failedValue);
  }

  disconnect() {
    clearTimeout(this.timer);
  }

  async #write(text) {
    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch (_error) {
        // Fall back below.
      }
    }

    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    let copied = false;
    try {
      copied = document.execCommand("copy");
    } catch (_error) {
      copied = false;
    }
    area.remove();
    return copied;
  }

  #announce(message) {
    if (!this.hasStatusTarget) return;

    this.statusTarget.textContent = message;
    this.statusTarget.classList.remove("hidden");
    clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.statusTarget.classList.add("hidden");
    }, STATUS_DELAY_MS);
  }
}
