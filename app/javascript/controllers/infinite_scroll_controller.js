import { Controller } from "@hotwired/stimulus";

// The next block of movements in the list: a turbo-frame that loads its URL
// when its button is pressed or when the user scrolls close to it. Nothing
// loads on its own before the user scrolls, so the first screen stays as it
// was served.
//
// Once loaded, the block stays through a page refresh. Saving a movement
// syncs its account, and the sync refreshes the page by morphing it: the
// fresh page only has the first block, so the blocks loaded by scrolling
// were emptied and the list jumped back to the top.
export default class extends Controller {
  static values = { url: String, margin: { type: Number, default: 600 } };

  connect() {
    this.loading = false;
    this.onScroll = this.onScroll.bind(this);
    this.keepWhenMorphing = this.keepWhenMorphing.bind(this);
    this.element.addEventListener(
      "turbo:before-morph-element",
      this.keepWhenMorphing,
    );
    // Captured on the document so it hears the scroll of whichever element
    // scrolls the page (the main panel on a computer, the window on a phone).
    document.addEventListener("scroll", this.onScroll, {
      capture: true,
      passive: true,
    });
  }

  disconnect() {
    document.removeEventListener("scroll", this.onScroll, { capture: true });
    this.element.removeEventListener(
      "turbo:before-morph-element",
      this.keepWhenMorphing,
    );
  }

  keepWhenMorphing(event) {
    if (event.target === this.element && this.element.src) {
      event.preventDefault();
    }
  }

  onScroll() {
    if (this.loading) return;

    const distance =
      this.element.getBoundingClientRect().top - window.innerHeight;
    if (distance < this.marginValue) this.load();
  }

  load(event) {
    event?.preventDefault();
    if (this.loading) return;

    this.loading = true;
    this.element.src = this.urlValue;
  }
}
