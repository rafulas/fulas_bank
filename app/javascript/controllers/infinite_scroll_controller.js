import { Controller } from "@hotwired/stimulus";

// The next block of movements in the list: a turbo-frame that loads its URL
// when its button is pressed or when the list comes within a few screens of
// it, so the block is usually there before the user reaches it. Checked as
// the page scrolls, and once when the block appears (after the page has
// settled): a short first block brings the next one in the background.
//
// Once loaded, the block stays through a page refresh. Saving a movement
// syncs its account, and the sync refreshes the page by morphing it: the
// fresh page only has the first block, so the blocks loaded by scrolling
// were emptied and the list jumped back to the top.
export default class extends Controller {
  static values = { url: String, margin: { type: Number, default: 2500 } };

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
    this.settleTimer = setTimeout(this.onScroll, 300);
  }

  disconnect() {
    clearTimeout(this.settleTimer);
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
    // In a hidden tab every block would look close and load the next one,
    // all the way down the history.
    if (this.element.getClientRects().length === 0) return;

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
