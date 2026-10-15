import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import {
  CHART_TOOLTIP_CONTEXT_CLASSES,
  CHART_TOOLTIP_VALUE_CLASSES,
  createChartTooltip,
} from "utils/chart_tooltip";

// "Evolución y rentabilidad" of an investment account, like the bank's page.
//
// The series arrives from Investment::Performance as [date, value, flow] per
// day (flow = money put in that day). For the chosen period this script
// works out, as the Ruby model does:
//   - gained = value at the end − value before the period − money put in;
//   - return (Modified Dietz) = gained / (value before + each contribution
//     weighted by the share of the period it was invested).
// The chart shows the value (€) or the return so far (%), and hovering a day
// shows what was invested, gained and put in up to then.
export default class extends Controller {
  static targets = [
    "canvas",
    "periodButton",
    "unitButton",
    "custom",
    "from",
    "to",
    "range",
    "gain",
    "returnRatio",
    "contributed",
  ];
  static values = {
    series: Array,
    currency: String,
    today: String,
    labels: Object,
    period: { type: String, default: "ytd" },
    unit: { type: String, default: "money" },
  };

  connect() {
    this._points = this.seriesValue.map(([date, value, flow]) => ({
      date: this._parseDate(date),
      value,
      flow,
    }));
    this._money = new Intl.NumberFormat(this._locale(), {
      style: "currency",
      currency: this.currencyValue || "EUR",
    });
    this._percent = new Intl.NumberFormat(this._locale(), {
      style: "percent",
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
    this._dateFormat = new Intl.DateTimeFormat(this._locale(), {
      day: "numeric",
      month: "long",
      year: "numeric",
    });

    if (typeof ResizeObserver !== "undefined") {
      this._observer = new ResizeObserver(() => this._draw());
      this._observer.observe(this.canvasTarget);
    }
    this._refresh();
  }

  disconnect() {
    this._observer?.disconnect();
  }

  selectPeriod(event) {
    this.periodValue = event.params.period;
  }

  selectUnit(event) {
    this.unitValue = event.params.unit;
  }

  selectCustom() {
    if (this.periodValue === "custom") this._refresh();
  }

  periodValueChanged() {
    this._refresh();
  }

  unitValueChanged() {
    this._refresh();
  }

  _locale() {
    return document.documentElement.lang || undefined;
  }

  _parseDate(value) {
    const [year, month, day] = value.split("-").map(Number);
    return new Date(year, month - 1, day);
  }

  _range() {
    const today = this._parseDate(this.todayValue);
    switch (this.periodValue) {
      case "1m":
        return [d3.timeMonth.offset(today, -1), today];
      case "3m":
        return [d3.timeMonth.offset(today, -3), today];
      case "1y":
        return [d3.timeYear.offset(today, -1), today];
      case "all":
        return [this._points[0]?.date || today, today];
      case "custom": {
        const from = this.hasFromTarget && this.fromTarget.value;
        const to = this.hasToTarget && this.toTarget.value;
        return [
          from ? this._parseDate(from) : this._points[0]?.date || today,
          to ? this._parseDate(to) : today,
        ];
      }
      default:
        return [new Date(today.getFullYear(), 0, 1), today];
    }
  }

  // Each point of the period with what had been put in and gained by then,
  // and the return so far.
  _computed() {
    const [from, to] = this._range();
    const inRange = this._points.filter(
      (point) => point.date >= from && point.date <= to,
    );
    if (inRange.length === 0) return [];

    const before = [...this._points]
      .reverse()
      .find((point) => point.date < inRange[0].date);
    const startValue = before ? before.value : 0;
    const startDate = before
      ? before.date
      : d3.timeDay.offset(inRange[0].date, -1);

    // Running sums, so each day's weighting is not recounted from the start:
    // Σ flow × (day − flow's day) = day × Σ flow − Σ flow × flow's day.
    let contributed = 0;
    let flowTimesDay = 0;
    return inRange.map((point) => {
      const day = d3.timeDay.count(startDate, point.date);
      contributed += point.flow;
      flowTimesDay += point.flow * day;
      const gain = point.value - startValue - contributed;
      const weighted = day > 0 ? (day * contributed - flowTimesDay) / day : 0;
      const base = startValue + weighted;
      return {
        ...point,
        contributed,
        gain,
        ratio: base > 0 ? gain / base : null,
      };
    });
  }

  _refresh() {
    if (!this._points) return;

    this.periodButtonTargets.forEach((button) => {
      const active =
        button.dataset.investmentPerformancePeriodParam === this.periodValue;
      button.setAttribute("aria-pressed", active ? "true" : "false");
      button.classList.toggle("bg-surface-inset", active);
      button.classList.toggle("text-primary", active);
    });
    this.unitButtonTargets.forEach((button) => {
      const active =
        button.dataset.investmentPerformanceUnitParam === this.unitValue;
      button.setAttribute("aria-pressed", active ? "true" : "false");
      button.classList.toggle("bg-inverse", active);
      button.classList.toggle("text-inverse", active);
    });
    if (this.hasCustomTarget)
      this.customTarget.hidden = this.periodValue !== "custom";

    this._data = this._computed();
    const last = this._data[this._data.length - 1];

    if (this.hasRangeTarget) {
      this.rangeTarget.textContent = this._data.length
        ? `${this.labelsValue.from} ${this._dateFormat.format(this._data[0].date)} ${this.labelsValue.to} ${this._dateFormat.format(last.date)}`
        : "";
    }
    this._setFigure(
      this.gainTarget,
      last ? this._money.format(last.gain) : "—",
      last?.gain,
    );
    this._setFigure(
      this.returnRatioTarget,
      last && last.ratio !== null ? this._percent.format(last.ratio) : "—",
      last?.ratio,
    );
    this.contributedTarget.textContent = last
      ? this._money.format(last.contributed)
      : "—";

    this._draw();
  }

  _setFigure(target, text, number) {
    target.textContent = text;
    target.classList.toggle(
      "text-success",
      typeof number === "number" && number >= 0,
    );
    target.classList.toggle(
      "text-destructive",
      typeof number === "number" && number < 0,
    );
  }

  _draw() {
    const root = this.canvasTarget;
    root.innerHTML = "";

    const points = (this._data || []).filter(
      (point) => this.unitValue === "money" || point.ratio !== null,
    );
    const width = root.clientWidth;
    const height = root.clientHeight;
    if (width <= 0 || height <= 0 || points.length === 0) return;

    const plotted = (point) =>
      this.unitValue === "money" ? point.value : point.ratio;
    const format = (number) =>
      this.unitValue === "money"
        ? this._money.format(number)
        : this._percent.format(number);

    const isDark =
      document.documentElement.getAttribute("data-theme") === "dark";
    const lineColor = isDark ? "#5eead4" : "#0d9488";
    const mutedColor = isDark ? "#a3a3a3" : "#737373";
    const gridColor = isDark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.08)";

    const margin = { top: 12, right: 12, bottom: 28, left: 64 };
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    const x = d3
      .scaleTime()
      .domain(d3.extent(points, (point) => point.date))
      .range([margin.left, margin.left + innerWidth]);
    if (points.length === 1)
      x.domain([
        d3.timeDay.offset(points[0].date, -1),
        d3.timeDay.offset(points[0].date, 1),
      ]);

    const [low, high] = d3.extent(points, plotted);
    const padding = Math.max((high - low) * 0.1, Math.abs(high) * 0.01, 0.0001);
    const y = d3
      .scaleLinear()
      .domain([low - padding, high + padding])
      .nice()
      .range([margin.top + innerHeight, margin.top]);

    const svg = d3
      .select(root)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("aria-hidden", "true");

    const yTicks = y.ticks(4);
    svg
      .append("g")
      .selectAll("line")
      .data(yTicks)
      .join("line")
      .attr("x1", margin.left)
      .attr("x2", margin.left + innerWidth)
      .attr("y1", (tick) => y(tick))
      .attr("y2", (tick) => y(tick))
      .attr("stroke", gridColor);
    const axisFormat =
      this.unitValue === "money"
        ? new Intl.NumberFormat(this._locale(), {
            notation: "compact",
            maximumFractionDigits: 1,
          })
        : this._percent;
    svg
      .append("g")
      .selectAll("text")
      .data(yTicks)
      .join("text")
      .attr("x", margin.left - 8)
      .attr("y", (tick) => y(tick))
      .attr("dy", "0.32em")
      .attr("text-anchor", "end")
      .attr("font-size", 11)
      .attr("fill", mutedColor)
      .text((tick) => axisFormat.format(tick));

    const spanDays = d3.timeDay.count(...x.domain());
    const tickFormat = new Intl.DateTimeFormat(
      this._locale(),
      spanDays > 400
        ? { month: "short", year: "2-digit" }
        : { day: "numeric", month: "short" },
    );
    const seen = new Set();
    const xTicks = x
      .ticks(Math.max(2, Math.floor(innerWidth / 90)))
      .filter((tick) => {
        const label = tickFormat.format(tick);
        if (seen.has(label)) return false;
        seen.add(label);
        return true;
      });
    svg
      .append("g")
      .selectAll("text")
      .data(xTicks)
      .join("text")
      .attr("x", (tick) => x(tick))
      .attr("y", height - 8)
      .attr("text-anchor", "middle")
      .attr("font-size", 11)
      .attr("fill", mutedColor)
      .text((tick) => tickFormat.format(tick));

    svg
      .append("path")
      .datum(points)
      .attr("fill", "none")
      .attr("stroke", lineColor)
      .attr("stroke-width", 1.75)
      .attr(
        "d",
        d3
          .line()
          .x((point) => x(point.date))
          .y((point) => y(plotted(point))),
      );

    const focus = svg.append("g").style("display", "none");
    focus
      .append("line")
      .attr("y1", margin.top)
      .attr("y2", margin.top + innerHeight)
      .attr("stroke", mutedColor)
      .attr("stroke-dasharray", "2 3");
    focus
      .append("circle")
      .attr("r", 5)
      .attr("fill", lineColor)
      .attr("stroke", isDark ? "#0a0a0a" : "#ffffff")
      .attr("stroke-width", 2);

    const tooltip = createChartTooltip(root);
    const bisect = d3.bisector((point) => point.date).center;
    const labels = this.labelsValue;

    const show = (event) => {
      const [pointerX] = d3.pointer(event, svg.node());
      const point = points[bisect(points, x.invert(pointerX))];
      if (!point) return;

      const px = x(point.date);
      const py = y(plotted(point));
      focus.style("display", null);
      focus.select("line").attr("x1", px).attr("x2", px);
      focus.select("circle").attr("cx", px).attr("cy", py);

      tooltip.innerHTML = `
        <div class="${CHART_TOOLTIP_CONTEXT_CLASSES}">${this._dateFormat.format(point.date)}</div>
        <div class="${CHART_TOOLTIP_VALUE_CLASSES}">${format(plotted(point))}</div>
        <div class="text-xs text-secondary mt-1 space-y-0.5 tabular-nums">
          <div>${labels.value}: ${this._money.format(point.value)}</div>
          <div>${labels.gain}: ${this._money.format(point.gain)}</div>
          <div>${labels.contributed}: ${this._money.format(point.contributed)}</div>
        </div>`;
      tooltip.style.display = "block";

      const cardWidth = tooltip.offsetWidth;
      const left = px + 12 + cardWidth > width ? px - 12 - cardWidth : px + 12;
      tooltip.style.left = `${Math.max(0, left)}px`;
      tooltip.style.top = `${Math.max(0, Math.min(py - 20, height - tooltip.offsetHeight))}px`;
    };

    const hide = () => {
      focus.style("display", "none");
      tooltip.style.display = "none";
    };

    svg
      .append("rect")
      .attr("x", margin.left)
      .attr("y", margin.top)
      .attr("width", innerWidth)
      .attr("height", innerHeight)
      .attr("fill", "transparent")
      .style("touch-action", "pan-y")
      .on("pointermove pointerdown", show)
      .on("pointerleave", hide);
  }
}
