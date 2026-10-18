import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";

// Fulas Bank: the spending pace of Planes. Draws, over the days of the month,
// the budget spread evenly (dashed, from 0 to the total on the last day) and
// what has been spent so far (solid; red once it is above the dashed line),
// plus a marker on today. Colours come from the design tokens through
// `currentColor`, so the chart follows light and dark themes.
//
// Data shape (MonthPlan#budget_pace):
//   { days: 31, total: 900.0, spent: [0, 12.5, ...], today: 18 | null }
export default class extends Controller {
  static values = { data: Object };

  connect() {
    if (typeof ResizeObserver !== "undefined") {
      this._observer = new ResizeObserver(() => this._draw());
      this._observer.observe(this.element);
    } else {
      this._draw();
    }
  }

  disconnect() {
    this._observer?.disconnect();
  }

  _draw() {
    const { days, total, spent, today } = this.dataValue;
    const width = this.element.clientWidth;
    const height = this.element.clientHeight;
    if (!width || !height || !days) return;

    d3.select(this.element).selectAll("svg").remove();

    const margin = { top: 6, right: 4, bottom: 6, left: 4 };
    const max = Math.max(total, d3.max(spent) || 0) * 1.05 || 1;
    const x = d3
      .scaleLinear()
      .domain([1, days])
      .range([margin.left, width - margin.right]);
    const y = d3
      .scaleLinear()
      .domain([0, max])
      .range([height - margin.bottom, margin.top]);

    const svg = d3
      .select(this.element)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("aria-hidden", "true");

    // The budget spread evenly over the month.
    svg
      .append("line")
      .attr("class", "text-secondary")
      .attr("stroke", "currentColor")
      .attr("stroke-width", 1.5)
      .attr("stroke-dasharray", "4 4")
      .attr("x1", x(1))
      .attr("y1", y(total / days))
      .attr("x2", x(days))
      .attr("y2", y(total));

    // What has been spent, day by day.
    const last = spent.length;
    const ahead = last > 0 && spent[last - 1] > (total * last) / days;
    const points = spent.map((value, index) => [index + 1, value]);
    svg
      .append("path")
      .datum(points)
      .attr("class", ahead ? "text-destructive" : "text-success")
      .attr("fill", "none")
      .attr("stroke", "currentColor")
      .attr("stroke-width", 2)
      .attr("stroke-linejoin", "round")
      .attr("stroke-linecap", "round")
      .attr(
        "d",
        d3
          .line()
          .x((d) => x(d[0]))
          .y((d) => y(d[1])),
      );

    // Today.
    if (today) {
      svg
        .append("line")
        .attr("class", "text-subdued")
        .attr("stroke", "currentColor")
        .attr("stroke-width", 1)
        .attr("x1", x(today))
        .attr("x2", x(today))
        .attr("y1", margin.top)
        .attr("y2", height - margin.bottom);
      if (last > 0) {
        svg
          .append("circle")
          .attr("class", ahead ? "text-destructive" : "text-success")
          .attr("fill", "currentColor")
          .attr("r", 3.5)
          .attr("cx", x(last))
          .attr("cy", y(spent[last - 1]));
      }
    }
  }
}
