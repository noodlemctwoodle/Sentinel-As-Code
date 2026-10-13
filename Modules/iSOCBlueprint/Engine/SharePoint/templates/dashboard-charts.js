/* dashboard-charts.js: the chart web part's renderers (Modules/iSOCBlueprint/WebParts/src/webparts/isocBlueprintChart/charts)
   bundled for the SharePoint dashboard by Modules/iSOCBlueprint/WebParts/Build-DashboardCharts.ps1. Do not edit;
   regenerate after changing the chart sources.
   sources-sha256: e7cc67656793cf495bfbcbcd545b1b9ed1d75ea145a726a63520a30e2e36abe4 */
(function(){
'use strict';
 var defs={};
 defs['ChartKit']=function(module,exports,require){
"use strict";
// Shared drawing helpers for the chart web part: escaping, reading loosely
// typed JSON, colours, text measuring and wrapping, and SVG fragments. Every
// chart builds a string of markup; anything taken from the chart data goes
// through esc() first.
Object.defineProperty(exports, "__esModule", { value: true });
exports.niceTicks = exports.legendHtml = exports.marker = exports.rect = exports.r = exports.svgText = exports.svgDoc = exports.nextId = exports.widest = exports.wrapText = exports.textWidth = exports.setTextMeasurer = exports.readableOn = exports.colourFor = exports.safeHref = exports.fmt = exports.esc = exports.list = exports.num = exports.str = exports.isNil = exports.SERIES = exports.FONT = void 0;
exports.FONT = '"Segoe UI", "Segoe UI Web (West European)", -apple-system, BlinkMacSystemFont, Roboto, "Helvetica Neue", sans-serif';
// The dashboard's series colours, so a chart reads the same on both.
exports.SERIES = [
    '#2563eb', '#0d9488', '#7c3aed', '#d97706', '#e11d48',
    '#0891b2', '#4f46e5', '#16a34a', '#ea580c', '#64748b'
];
// Labels that carry a meaning get the colour that meaning has elsewhere in
// the Blueprint; everything else takes the next series colour.
const NAMED = {
    critical: '#991b1b', high: '#dc2626', medium: '#ea580c', warning: '#d97706',
    low: '#ca8a04', info: '#2563eb', informational: '#2563eb',
    success: '#16a34a', succeeded: '#16a34a', failure: '#dc2626', failed: '#dc2626',
    truepositive: '#dc2626', falsepositive: '#16a34a', benignpositive: '#d97706',
    undetermined: '#64748b', unclassified: '#94a3b8', unknown: '#94a3b8',
    registered: '#16a34a', notregistered: '#dc2626', notmonitored: '#dc2626',
    open: '#d97706', closed: '#16a34a'
};
function isNil(value) {
    return value === undefined || value === null;
}
exports.isNil = isNil;
function str(value) {
    return isNil(value) ? '' : String(value);
}
exports.str = str;
function num(value) {
    const n = typeof value === 'number' ? value : parseFloat(str(value));
    return isFinite(n) ? n : 0;
}
exports.num = num;
function list(value) {
    return Array.isArray(value) ? value.filter((v) => !isNil(v)) : [];
}
exports.list = list;
function esc(value) {
    return str(value).replace(/[&<>"']/g, (c) => {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
}
exports.esc = esc;
function fmt(value) {
    const rounded = Math.round(value * 100) / 100;
    return rounded.toLocaleString('en-GB');
}
exports.fmt = fmt;
// Only links the publisher writes: web URLs, mail and site-relative paths.
function safeHref(href) {
    const h = str(href).trim();
    return /^(https?:\/\/|mailto:|\/)/i.test(h) ? h : undefined;
}
exports.safeHref = safeHref;
function colourFor(label, index) {
    const key = str(label).toLowerCase().replace(/[^a-z]/g, '');
    return NAMED[key] || exports.SERIES[index % exports.SERIES.length];
}
exports.colourFor = colourFor;
// Black or white, whichever reads better on a fill.
function readableOn(fill) {
    const m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(str(fill).trim());
    if (!m) {
        return '#111827';
    }
    const hex = m[1].length === 3 ? m[1].split('').map((c) => c + c).join('') : m[1];
    const r = parseInt(hex.substring(0, 2), 16);
    const g = parseInt(hex.substring(2, 4), 16);
    const b = parseInt(hex.substring(4, 6), 16);
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6 ? '#111827' : '#ffffff';
}
exports.readableOn = readableOn;
function estimateWidth(text, size, bold) {
    let w = 0;
    for (const ch of text) {
        w += /[A-Z@%MW]/.test(ch) ? 0.68 : /[ijlI.,:;'|! ]/.test(ch) ? 0.3 : /[0-9]/.test(ch) ? 0.56 : 0.54;
    }
    return w * size * (bold ? 1.06 : 1);
}
let measurer = estimateWidth;
// The web part passes a canvas-based measurer; tests and fallbacks estimate.
function setTextMeasurer(m) {
    measurer = m || estimateWidth;
}
exports.setTextMeasurer = setTextMeasurer;
function textWidth(text, size, bold = false) {
    return Math.ceil(measurer(text, size, bold));
}
exports.textWidth = textWidth;
// Greedy word wrap; '\n' in the text always breaks. A word longer than the
// line is cut rather than allowed to overflow.
function wrapText(text, maxWidth, size, bold = false) {
    const out = [];
    for (const para of str(text).split('\n')) {
        let line = '';
        for (const word of para.split(/\s+/).filter((w) => w.length > 0)) {
            const next = line ? line + ' ' + word : word;
            if (textWidth(next, size, bold) <= maxWidth) {
                line = next;
                continue;
            }
            if (line) {
                out.push(line);
            }
            let rest = word;
            while (textWidth(rest, size, bold) > maxWidth && rest.length > 1) {
                let cut = rest.length - 1;
                while (cut > 1 && textWidth(rest.substring(0, cut), size, bold) > maxWidth) {
                    cut--;
                }
                out.push(rest.substring(0, cut));
                rest = rest.substring(cut);
            }
            line = rest;
        }
        out.push(line);
    }
    return out;
}
exports.wrapText = wrapText;
function widest(lines, size, bold = false) {
    return lines.reduce((m, l) => Math.max(m, textWidth(l, size, bold)), 0);
}
exports.widest = widest;
let idCounter = 0;
// Marker and clip ids must be unique on the page, which can hold many charts.
function nextId(prefix) {
    idCounter++;
    return 'ibc-' + prefix + '-' + idCounter;
}
exports.nextId = nextId;
// The drawing scales down with its column to two thirds of its size, then
// the column scrolls sideways (see renderChart), so text stays readable.
function svgDoc(width, height, label, body) {
    const w = Math.ceil(width);
    const h = Math.ceil(height);
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + w + ' ' + h + '" width="' + w + '" height="' + h + '"' +
        ' style="display:block;width:100%;max-width:' + w + 'px;min-width:' + Math.round(w * 0.66) + 'px;height:auto;overflow:visible"' +
        ' role="img" aria-label="' + esc(label) + '">' +
        '<title>' + esc(label) + '</title>' + body + '</svg>';
}
exports.svgDoc = svgDoc;
// One <text> per block of lines, vertically centred on y.
function svgText(x, y, lines, opts) {
    const size = opts.size || 12;
    const lh = opts.lineHeight || Math.round(size * 1.3);
    const top = y - ((lines.length - 1) * lh) / 2 + size * 0.35;
    let out = '<text x="' + r(x) + '" y="' + r(top) + '" font-size="' + size + '"' +
        (opts.weight ? ' font-weight="' + opts.weight + '"' : '') +
        (opts.fill ? ' fill="' + esc(opts.fill) + '"' : '') +
        (opts.anchor ? ' text-anchor="' + opts.anchor + '"' : '') + '>';
    lines.forEach((line, i) => {
        out += '<tspan x="' + r(x) + '"' + (i > 0 ? ' dy="' + lh + '"' : '') + '>' + esc(line) + '</tspan>';
    });
    return out + '</text>';
}
exports.svgText = svgText;
function r(n) {
    return String(Math.round(n * 10) / 10);
}
exports.r = r;
function rect(x, y, w, h, attrs) {
    return '<rect x="' + r(x) + '" y="' + r(y) + '" width="' + r(Math.max(0, w)) + '" height="' + r(Math.max(0, h)) + '" ' + attrs + '/>';
}
exports.rect = rect;
// An arrowhead for edges: 'arrow' (filled), 'triangle' (hollow, for
// inheritance), 'diamond' (filled), 'odiamond' (hollow) or 'cross'.
function marker(id, shape, colour, surface) {
    const c = esc(colour);
    const s = esc(surface);
    let path;
    switch (shape) {
        case 'triangle':
            path = '<path d="M0,0 L12,6 L0,12 Z" fill="' + s + '" stroke="' + c + '" stroke-width="1.4"/>';
            break;
        case 'diamond':
            path = '<path d="M0,6 L6,0 L12,6 L6,12 Z" fill="' + c + '"/>';
            break;
        case 'odiamond':
            path = '<path d="M0,6 L6,0 L12,6 L6,12 Z" fill="' + s + '" stroke="' + c + '" stroke-width="1.4"/>';
            break;
        case 'cross':
            path = '<path d="M2,2 L10,10 M10,2 L2,10" stroke="' + c + '" stroke-width="1.8"/>';
            break;
        default: path = '<path d="M0,1 L11,6 L0,11 Z" fill="' + c + '"/>';
    }
    return '<marker id="' + id + '" viewBox="0 0 12 12" refX="11" refY="6" markerWidth="10" markerHeight="10" orient="auto-start-reverse" markerUnits="userSpaceOnUse">' + path + '</marker>';
}
exports.marker = marker;
function legendHtml(items, theme) {
    if (!items.length) {
        return '';
    }
    return '<div style="display:flex;flex-wrap:wrap;gap:6px 16px;margin-top:10px;font-size:13px;color:' + esc(theme.text) + '">' +
        items.map((i) => '<span style="display:inline-flex;align-items:center;gap:6px">' +
            '<i style="display:inline-block;width:10px;height:10px;border-radius:3px;background:' + esc(i.colour) + '"></i>' +
            esc(i.label) + (i.value ? '<span style="color:' + esc(theme.muted) + '">' + esc(i.value) + '</span>' : '') +
            '</span>').join('') +
        '</div>';
}
exports.legendHtml = legendHtml;
// Round numbers for an axis from lo to hi, about `count` of them; whole
// numbers only when the values are counts.
function niceTicks(lo, hi, count, whole = false) {
    if (hi <= lo) {
        hi = lo + 1;
    }
    const raw = (hi - lo) / Math.max(1, count);
    const mag = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10));
    const norm = raw / mag;
    let step = (norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10) * mag;
    if (whole) {
        step = Math.max(1, Math.round(step));
    }
    const ticks = [];
    for (let v = Math.floor(lo / step) * step; v <= hi + step * 0.001; v += step) {
        ticks.push(Math.round(v / step) * step);
    }
    return ticks;
}
exports.niceTicks = niceTicks;

};
 defs['ChartTypes']=function(module,exports,require){
"use strict";
// The chart block of the Blueprint section model, as the publisher stores it
// in the web part's chartJson property. Shapes follow
// Docs/Modules/iSOCBlueprint/Section-Model.md (Charts). The JSON carries null for
// absent values, so every field is read as optional and checked at runtime.
Object.defineProperty(exports, "__esModule", { value: true });

};
 defs['ClassChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderClass = void 0;
const ChartKit_1 = require("./ChartKit");
const GraphDraw_1 = require("./GraphDraw");
const NoteNode_1 = require("./NoteNode");
const MONO = 'Consolas, "Cascadia Mono", Menlo, monospace';
// Classes as name-and-members boxes, top to bottom, with UML ends on the
// relations: a hollow triangle for inheritance or realisation, diamonds for
// composition and aggregation, arrows for association and dependency.
function renderClass(data, theme, label) {
    const classes = (0, ChartKit_1.list)(data && data.classes);
    const nodes = [];
    const known = {};
    const add = (c) => {
        const name = (0, ChartKit_1.str)(c.name);
        if (!name || known[name]) {
            return;
        }
        known[name] = true;
        const members = (0, ChartKit_1.list)(c.members).map(ChartKit_1.str);
        const w = Math.max((0, ChartKit_1.widest)([name], 13, true), (0, ChartKit_1.widest)(members, 12) * 1.15) + 26;
        const h = 32 + (members.length ? members.length * 16 + 12 : 0);
        nodes.push({ id: name, w: w, h: h, x: 0, y: 0, rank: 0, draw: (b) => classBox(b, name, members, theme) });
    };
    classes.forEach(add);
    const edges = [];
    (0, ChartKit_1.list)(data && data.relations).forEach((rel) => {
        add({ name: (0, ChartKit_1.str)(rel.from) });
        add({ name: (0, ChartKit_1.str)(rel.to) });
        const kind = (0, ChartKit_1.str)(rel.kind);
        const left = endShape(kind.substring(0, 2), true);
        const right = endShape(kind.substring(kind.length - 2), false);
        const dashed = kind.indexOf('..') >= 0;
        // The end with the triangle or diamond (the parent or whole) goes on top.
        if (right && !left) {
            edges.push({ from: (0, ChartKit_1.str)(rel.to), to: (0, ChartKit_1.str)(rel.from), start: right, dashed: dashed, label: (0, ChartKit_1.str)(rel.label) || undefined });
        }
        else {
            edges.push({ from: (0, ChartKit_1.str)(rel.from), to: (0, ChartKit_1.str)(rel.to), start: left, end: right, dashed: dashed, label: (0, ChartKit_1.str)(rel.label) || undefined });
        }
    });
    (0, ChartKit_1.list)(data && data.notes).forEach((n, i) => {
        const id = '__note' + i;
        nodes.push((0, NoteNode_1.noteNode)(id, (0, ChartKit_1.str)(n.text), theme));
        if ((0, ChartKit_1.str)(n.for) && known[(0, ChartKit_1.str)(n.for)]) {
            edges.push({ from: (0, ChartKit_1.str)(n.for), to: id, dashed: true });
        }
    });
    return (0, GraphDraw_1.drawGraph)(nodes, edges, [], true, theme, label);
}
exports.renderClass = renderClass;
// The marker for one end of a Mermaid relation ('<|', '*', 'o', '<' on the
// left; '|>', '*', 'o', '>' on the right).
function endShape(end, left) {
    if (left ? end === '<|' : end === '|>') {
        return 'triangle';
    }
    const c = left ? end.charAt(0) : end.charAt(end.length - 1);
    if (c === '*') {
        return 'diamond';
    }
    if (c === 'o') {
        return 'odiamond';
    }
    if (left ? c === '<' : c === '>') {
        return 'arrow';
    }
    return undefined;
}
function classBox(b, name, members, theme) {
    let out = (0, ChartKit_1.rect)(b.x, b.y, b.w, b.h, 'rx="6" fill="' + (0, ChartKit_1.esc)(theme.surface) + '" stroke="' + (0, ChartKit_1.esc)(theme.accent) + '" stroke-width="1.5"') +
        (0, ChartKit_1.rect)(b.x, b.y, b.w, 32, 'rx="6" fill="' + (0, ChartKit_1.esc)(theme.accent) + '" fill-opacity="0.12"') +
        (0, ChartKit_1.svgText)(b.x + b.w / 2, b.y + 16, [name], { size: 13, weight: 600, fill: theme.text, anchor: 'middle' });
    if (members.length) {
        out += '<line x1="' + (0, ChartKit_1.r)(b.x) + '" y1="' + (0, ChartKit_1.r)(b.y + 32) + '" x2="' + (0, ChartKit_1.r)(b.x + b.w) + '" y2="' + (0, ChartKit_1.r)(b.y + 32) + '" stroke="' + (0, ChartKit_1.esc)(theme.line) + '"/>' +
            '<g font-family="' + (0, ChartKit_1.esc)(MONO) + '">' +
            (0, ChartKit_1.svgText)(b.x + 13, b.y + 32 + (b.h - 32) / 2, members, { size: 12, fill: theme.text, lineHeight: 16 }) + '</g>';
    }
    return out;
}

};
 defs['FlowChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderFlowchart = void 0;
const ChartKit_1 = require("./ChartKit");
const GraphDraw_1 = require("./GraphDraw");
const LINE = 16;
// Boxes and arrows, in subgraph groups, with the colours and links the
// renderer gave them. TB, TD and BT run top to bottom; anything else runs
// left to right.
function renderFlowchart(data, theme, label) {
    const vertical = /^(TB|TD|BT)$/i.test((0, ChartKit_1.str)(data && data.direction));
    const nodes = (0, ChartKit_1.list)(data && data.nodes).map((n) => {
        const lines = (0, ChartKit_1.wrapText)((0, ChartKit_1.str)(n.label) || (0, ChartKit_1.str)(n.id), 190, 12);
        return {
            id: (0, ChartKit_1.str)(n.id), w: (0, ChartKit_1.widest)(lines, 12) + 26, h: lines.length * LINE + 16, group: (0, ChartKit_1.str)(n.group) || undefined,
            x: 0, y: 0, rank: 0,
            draw: (b) => drawNode(b, n, lines, theme)
        };
    });
    const edges = (0, ChartKit_1.list)(data && data.edges).map((e) => ({
        from: (0, ChartKit_1.str)(e.from), to: (0, ChartKit_1.str)(e.to), label: (0, ChartKit_1.str)(e.label) || undefined,
        dashed: e.style === 'dotted', thick: e.style === 'thick', end: e.arrow === false ? undefined : 'arrow'
    }));
    const groups = (0, ChartKit_1.list)(data && data.groups)
        .map((g) => ({
        id: (0, ChartKit_1.str)(g.id), label: (0, ChartKit_1.str)(g.label) || (0, ChartKit_1.str)(g.id), parent: (0, ChartKit_1.str)(g.parent) || undefined
    }));
    return (0, GraphDraw_1.drawGraph)(nodes, edges, groups, vertical, theme, label);
}
exports.renderFlowchart = renderFlowchart;
function drawNode(b, n, lines, theme) {
    const fill = (0, ChartKit_1.str)(n.fill);
    const stroke = (0, ChartKit_1.str)(n.stroke) || fill || theme.accent;
    const ink = (0, ChartKit_1.str)(n.color) || (fill ? (0, ChartKit_1.readableOn)(fill) : theme.text);
    const href = (0, ChartKit_1.safeHref)(n.href);
    let out = (0, ChartKit_1.rect)(b.x, b.y, b.w, b.h, 'rx="8" fill="' + (0, ChartKit_1.esc)(fill || theme.surface) + '" stroke="' + (0, ChartKit_1.esc)(stroke) + '" stroke-width="1.5"');
    if (!fill) {
        out += (0, ChartKit_1.rect)(b.x, b.y, b.w, b.h, 'rx="8" fill="' + (0, ChartKit_1.esc)(theme.accent) + '" fill-opacity="0.07"');
    }
    out += (0, ChartKit_1.svgText)(b.x + b.w / 2, b.y + b.h / 2, lines, {
        size: 12, fill: ink, anchor: 'middle', lineHeight: LINE, weight: href ? 600 : undefined
    });
    const tip = (0, ChartKit_1.str)(n.tooltip) || (href ? 'Open ' + (0, ChartKit_1.str)(n.label || n.id).replace(/\n/g, ' ') : '');
    if (tip) {
        out = '<title>' + (0, ChartKit_1.esc)(tip) + '</title>' + out;
    }
    return href
        ? '<a href="' + (0, ChartKit_1.esc)(href) + '" style="cursor:pointer">' + out + '</a>'
        : '<g>' + out + '</g>';
}

};
 defs['GanttChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderGantt = void 0;
const ChartKit_1 = require("./ChartKit");
const DAY = 86400000;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const ROW = 26;
const PLOT_W = 560;
// Room after the axis for the date beside a bar that ends near it.
const DATE_W = 84;
// Tasks on a date axis, by section. A task's length may be negative (a
// deadline already passed); the bar then runs back from its start. Each
// bar is labelled with the date it marks.
function renderGantt(data, theme, label) {
    const rows = [];
    const ends = {};
    let previous = NaN;
    (0, ChartKit_1.list)(data && data.sections).forEach((s) => {
        if ((0, ChartKit_1.str)(s.name)) {
            rows.push({ heading: (0, ChartKit_1.str)(s.name) });
        }
        (0, ChartKit_1.list)(s.tasks).forEach((t) => {
            const start = startOf((0, ChartKit_1.str)(t.start), ends, previous);
            if (isNaN(start)) {
                return;
            }
            const days = lengthInDays((0, ChartKit_1.str)(t.length));
            const end = start + days * DAY;
            const tags = (0, ChartKit_1.list)(t.tags).map(ChartKit_1.str);
            const task = {
                label: (0, ChartKit_1.str)(t.label), tags: tags, from: Math.min(start, end), to: Math.max(start, end),
                date: days >= 0 && days <= 1 ? start : end,
                milestone: tags.indexOf('milestone') >= 0 || days === 0
            };
            if ((0, ChartKit_1.str)(t.id)) {
                ends[(0, ChartKit_1.str)(t.id)] = Math.max(start, end);
            }
            previous = Math.max(start, end);
            rows.push({ task: task });
        });
    });
    const tasks = rows.filter((x) => !!x.task).map((x) => x.task);
    if (!tasks.length) {
        return '';
    }
    let lo = Math.min(...tasks.map((t) => t.from));
    let hi = Math.max(...tasks.map((t) => t.to));
    if (hi - lo < 30 * DAY) {
        lo -= 15 * DAY;
        hi += 15 * DAY;
    }
    const pad = (hi - lo) * 0.04;
    lo -= pad;
    hi += pad;
    const labelW = Math.min(260, (0, ChartKit_1.widest)(tasks.map((t) => t.label), 12)) + 14;
    // A long task name wraps onto as many lines as it needs; its row grows.
    const lineSets = rows.map((row) => (row.task ? (0, ChartKit_1.wrapText)(row.task.label, labelW - 14, 12) : []));
    const heights = lineSets.map((l) => Math.max(ROW, l.length * 14 + 12));
    const offsets = [];
    let total = 0;
    heights.forEach((h) => { offsets.push(total); total += h; });
    const top = 26;
    const x = (t) => labelW + ((t - lo) / (hi - lo)) * PLOT_W;
    const height = top + total + 8;
    let body = '';
    ticks(lo, hi).forEach((t) => {
        body += '<line x1="' + (0, ChartKit_1.r)(x(t)) + '" y1="' + (top - 6) + '" x2="' + (0, ChartKit_1.r)(x(t)) + '" y2="' + (0, ChartKit_1.r)(height - 8) + '" stroke="' + (0, ChartKit_1.esc)(theme.line) + '"/>';
        body += (0, ChartKit_1.svgText)(x(t), 10, [formatAxis(t, (0, ChartKit_1.str)(data.axisFormat))], { size: 11, fill: theme.muted, anchor: 'middle' });
    });
    rows.forEach((row, i) => {
        const y = top + offsets[i];
        const mid = y + heights[i] / 2;
        if (row.heading) {
            body += (0, ChartKit_1.svgText)(0, mid, [row.heading.toUpperCase()], { size: 11, weight: 600, fill: theme.muted });
            return;
        }
        const t = row.task;
        const colour = t.tags.indexOf('crit') >= 0 ? '#dc2626' : t.tags.indexOf('done') >= 0 ? '#94a3b8' : theme.accent;
        body += (0, ChartKit_1.svgText)(labelW - 12, mid, lineSets[i], { size: 12, fill: theme.text, anchor: 'end', lineHeight: 14 });
        const tip = '<title>' + (0, ChartKit_1.esc)(t.label + ': ' + formatDay(t.date)) + '</title>';
        let right;
        if (t.milestone) {
            const cx = x(t.date);
            const cy = mid;
            body += '<path d="M' + (0, ChartKit_1.r)(cx) + ',' + (0, ChartKit_1.r)(cy - 7) + ' L' + (0, ChartKit_1.r)(cx + 7) + ',' + (0, ChartKit_1.r)(cy) + ' L' + (0, ChartKit_1.r)(cx) + ',' + (0, ChartKit_1.r)(cy + 7) + ' L' + (0, ChartKit_1.r)(cx - 7) + ',' + (0, ChartKit_1.r)(cy) + ' Z" fill="' + (0, ChartKit_1.esc)(colour) + '">' + tip + '</path>';
            right = cx + 8;
        }
        else {
            const x0 = x(t.from);
            const w = Math.max(4, x(t.to) - x0);
            body += (0, ChartKit_1.rect)(x0, mid - ROW / 2 + 6, w, ROW - 12, 'rx="4" fill="' + (0, ChartKit_1.esc)(colour) + '"' + (t.tags.indexOf('active') >= 0 ? '' : ' fill-opacity="0.85"')).replace('/>', '>' + tip + '</rect>');
            right = x0 + w;
        }
        const text = formatDay(t.date);
        const fits = right + 6 + (0, ChartKit_1.textWidth)(text, 11) <= labelW + PLOT_W + DATE_W;
        body += (0, ChartKit_1.svgText)(fits ? right + 6 : (t.milestone ? x(t.date) - 9 : x(t.from) - 6), mid, [text], { size: 11, fill: theme.muted, anchor: fits ? 'start' : 'end' });
    });
    return (0, ChartKit_1.svgDoc)(labelW + PLOT_W + DATE_W, height, label, body);
}
exports.renderGantt = renderGantt;
function parseDay(text) {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text.trim());
    if (m) {
        return Date.UTC(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
    }
    const t = Date.parse(text);
    return isNaN(t) ? NaN : t;
}
// A start is a date, 'after id ...' (the latest end of those tasks), or
// absent (straight after the previous task).
function startOf(text, ends, previous) {
    const after = /^after\s+(.+)$/i.exec(text.trim());
    if (after) {
        const known = after[1].split(/\s+/).filter((id) => ends[id] !== undefined).map((id) => ends[id]);
        return known.length ? Math.max(...known) : previous;
    }
    return text.trim() ? parseDay(text) : previous;
}
function lengthInDays(text) {
    const m = /^(-?\d+(?:\.\d+)?)\s*(ms|s|m|h|d|w|M|y)?$/.exec(text.trim());
    if (!m) {
        return 1;
    }
    const n = parseFloat(m[1]);
    const per = { ms: 1 / DAY, s: 1 / 86400, m: 1 / 1440, h: 1 / 24, d: 1, w: 7, M: 30, y: 365 };
    return n * (per[m[2] || 'd'] || 1);
}
// First-of-month ticks, every one to 24 months, about eight in all.
function ticks(lo, hi) {
    const months = (hi - lo) / (30 * DAY);
    const steps = [1, 2, 3, 6, 12, 24];
    let step = steps[steps.length - 1];
    for (const s of steps) {
        if (months / s <= 8) {
            step = s;
            break;
        }
    }
    const d = new Date(lo);
    let y = d.getUTCFullYear();
    let m = d.getUTCMonth() + 1;
    const out = [];
    for (let guard = 0; guard < 200; guard++) {
        if (m > 11) {
            y += Math.floor(m / 12);
            m = m % 12;
        }
        const t = Date.UTC(y, m, 1);
        if (t > hi) {
            break;
        }
        if (step < 12 ? m % step === 0 : m === 0 && y % (step / 12) === 0) {
            out.push(t);
        }
        m++;
    }
    return out;
}
function formatDay(t) {
    const d = new Date(t);
    return d.getUTCDate() + ' ' + MONTHS[d.getUTCMonth()] + ' ' + d.getUTCFullYear();
}
// The few strftime codes Mermaid axis formats use.
function formatAxis(t, format) {
    const d = new Date(t);
    const f = format || '%b %Y';
    return f.replace(/%([YymbBde])/g, (_m, c) => {
        switch (c) {
            case 'Y': return String(d.getUTCFullYear());
            case 'y': return String(d.getUTCFullYear()).substring(2);
            case 'm': return ('0' + (d.getUTCMonth() + 1)).slice(-2);
            case 'b': return MONTHS[d.getUTCMonth()];
            case 'B': return MONTHS[d.getUTCMonth()];
            case 'd': return ('0' + d.getUTCDate()).slice(-2);
            default: return String(d.getUTCDate());
        }
    });
}

};
 defs['GraphDraw']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.drawGraph = void 0;
const GraphLayout_1 = require("./GraphLayout");
const ChartKit_1 = require("./ChartKit");
const PAD = 14;
const PAD_TOP = 26;
function drawGraph(nodes, edges, groups, vertical, theme, label) {
    if (!nodes.length) {
        return '';
    }
    // Each label's size, so the layout can give a long edge's label room.
    edges.forEach((e) => {
        if (!e.label) {
            return;
        }
        const parts = e.label.split('\n');
        e.labelW = parts.reduce((m, t) => Math.max(m, (0, ChartKit_1.textWidth)(t, 11)), 0) + 12;
        e.labelH = parts.length * 14 + 8;
    });
    const labelled = edges.some((e) => !!e.label);
    const size = (0, GraphLayout_1.layoutGraph)(nodes, edges, {
        vertical: vertical,
        rankGap: vertical ? (labelled ? 70 : 54) : (labelled ? 110 : 70),
        nodeGap: vertical ? 28 : 16,
        groupGap: PAD + PAD_TOP + 14,
        groupOrder: groups.map((g) => g.id)
    });
    const byId = {};
    nodes.forEach((n) => { byId[n.id] = n; });
    // Group boxes, innermost first so a parent can wrap its children's boxes.
    const boxes = {};
    const parentOf = {};
    groups.forEach((g) => { parentOf[g.id] = g.parent; });
    const depthOf = (g) => {
        let d = 0;
        for (let p = g.parent; p && d < 20; p = parentOf[p]) {
            d++;
        }
        return d;
    };
    const ordered = groups.slice().sort((a, b) => depthOf(b) - depthOf(a));
    ordered.forEach((g) => {
        const parts = [];
        nodes.forEach((n) => { if (n.group === g.id) {
            parts.push({ x0: n.x, y0: n.y, x1: n.x + n.w, y1: n.y + n.h });
        } });
        groups.forEach((c) => { if (c.parent === g.id && boxes[c.id]) {
            parts.push(boxes[c.id]);
        } });
        if (!parts.length) {
            return;
        }
        const b = parts.reduce((m, x) => ({ x0: Math.min(m.x0, x.x0), y0: Math.min(m.y0, x.y0), x1: Math.max(m.x1, x.x1), y1: Math.max(m.y1, x.y1) }));
        const titleW = (0, ChartKit_1.textWidth)(g.label, 12, true) + PAD * 2;
        boxes[g.id] = { x0: b.x0 - PAD, y0: b.y0 - PAD_TOP, x1: Math.max(b.x1 + PAD, b.x0 - PAD + titleW), y1: b.y1 + PAD };
    });
    const arrowId = (0, ChartKit_1.nextId)('arrow');
    const ends = {};
    const endRef = (shape) => {
        if (!shape) {
            return '';
        }
        if (!ends[shape]) {
            ends[shape] = shape === 'arrow' ? arrowId : (0, ChartKit_1.nextId)(shape);
        }
        return 'url(#' + ends[shape] + ')';
    };
    let lane = 0;
    let lines = '';
    let labels = '';
    let extent = { x0: 0, y0: 0, x1: size.width, y1: size.height };
    edges.forEach((e) => {
        const a = byId[e.from];
        const b = byId[e.to];
        if (!a || !b || a === b) {
            return;
        }
        const around = !!e.back || b.rank <= a.rank;
        const myLane = around ? lane++ : 0;
        // A loop goes round whichever side of the drawing its ends are nearer.
        const before = vertical
            ? (a.x + b.x + (a.w + b.w) / 2) / 2 < size.width / 2
            : (a.y + b.y + (a.h + b.h) / 2) / 2 < size.height / 2;
        const far = 36 + myLane * 12 + (e.label ? ((vertical ? e.labelW : e.labelH) || 0) : 0);
        const p = around ? (0, GraphLayout_1.loopPath)(a, b, vertical, far, before) : (0, GraphLayout_1.forwardPath)(a, b, e.via || [], vertical);
        const at = !around && e.labelAt
            ? { x: e.labelAt.x + e.labelAt.w / 2, y: e.labelAt.y + e.labelAt.h / 2 }
            : p.mid;
        if (around) {
            // The curve's control points sit `far` past the nodes; the curve itself
            // reaches three quarters of the way, and its label is centred there.
            if (vertical) {
                extent = before
                    ? { x0: Math.min(extent.x0, Math.min(a.x, b.x) - far), y0: extent.y0, x1: extent.x1, y1: extent.y1 }
                    : { x0: extent.x0, y0: extent.y0, x1: Math.max(extent.x1, Math.max(a.x + a.w, b.x + b.w) + far), y1: extent.y1 };
            }
            else {
                extent = before
                    ? { x0: extent.x0, y0: Math.min(extent.y0, Math.min(a.y, b.y) - far), x1: extent.x1, y1: extent.y1 }
                    : { x0: extent.x0, y0: extent.y0, x1: extent.x1, y1: Math.max(extent.y1, Math.max(a.y + a.h, b.y + b.h) + far) };
            }
        }
        const startRef = endRef(e.start);
        const endUrl = endRef(e.end);
        lines += '<path d="' + p.d + '" fill="none" stroke="' + (0, ChartKit_1.esc)(theme.muted) + '" stroke-width="' + (e.thick ? 3 : 1.5) + '"' +
            (e.dashed ? ' stroke-dasharray="5 4"' : '') +
            (startRef ? ' marker-start="' + startRef + '"' : '') + (endUrl ? ' marker-end="' + endUrl + '"' : '') + '/>';
        if (e.label) {
            const parts = e.label.split('\n');
            const w = (e.labelW || 0) - 2;
            const h = (e.labelH || 0) - 2;
            labels += (0, ChartKit_1.rect)(at.x - w / 2, at.y - h / 2, w, h, 'rx="4" fill="' + (0, ChartKit_1.esc)(theme.surface) + '" stroke="' + (0, ChartKit_1.esc)(theme.line) + '"') +
                (0, ChartKit_1.svgText)(at.x, at.y, parts, { size: 11, fill: theme.muted, anchor: 'middle', lineHeight: 14 });
        }
    });
    let groupSvg = '';
    groups.slice().sort((a, b) => depthOf(a) - depthOf(b)).forEach((g) => {
        const b = boxes[g.id];
        if (!b) {
            return;
        }
        extent = { x0: Math.min(extent.x0, b.x0), y0: Math.min(extent.y0, b.y0), x1: Math.max(extent.x1, b.x1), y1: Math.max(extent.y1, b.y1) };
        groupSvg += (0, ChartKit_1.rect)(b.x0, b.y0, b.x1 - b.x0, b.y1 - b.y0, 'rx="10" fill="' + (0, ChartKit_1.esc)(theme.accent) + '" fill-opacity="' + (theme.dark ? '0.08' : '0.04') + '" stroke="' + (0, ChartKit_1.esc)(theme.line) + '" stroke-width="1.2"') +
            (0, ChartKit_1.svgText)(b.x0 + PAD, b.y0 + 13, [g.label], { size: 12, weight: 600, fill: theme.muted });
    });
    let defs = '';
    Object.keys(ends).forEach((shape) => { defs += (0, ChartKit_1.marker)(ends[shape], shape, theme.muted, theme.surface); });
    const nodeSvg = nodes.map((n) => n.draw(n)).join('');
    const dx = 4 - extent.x0;
    const dy = 4 - extent.y0;
    return (0, ChartKit_1.svgDoc)(extent.x1 - extent.x0 + 8, extent.y1 - extent.y0 + 8, label, (defs ? '<defs>' + defs + '</defs>' : '') +
        '<g transform="translate(' + (0, ChartKit_1.r)(dx) + ',' + (0, ChartKit_1.r)(dy) + ')">' + groupSvg + lines + nodeSvg + labels + '</g>');
}
exports.drawGraph = drawGraph;

};
 defs['GraphLayout']=function(module,exports,require){
"use strict";
// A small layered (Sugiyama-style) layout for the node-and-edge diagrams:
// break cycles, rank nodes by longest path, give an edge that skips ranks a
// placeholder in each rank it crosses (so it is routed round the nodes there,
// and a long edge's label has room of its own), order each rank to cut
// crossings while keeping a group's nodes together, then place the ranks side
// by side (left to right) or one under another (top to bottom).
Object.defineProperty(exports, "__esModule", { value: true });
exports.loopPath = exports.forwardPath = exports.layoutGraph = void 0;
// Positions nodes in place (x, y are top-left) and annotates the edges.
// Returns the drawing's size.
function layoutGraph(nodes, edges, opts) {
    const byId = {};
    nodes.forEach((n) => { byId[n.id] = n; n.rank = 0; });
    const live = edges.filter((e) => !!byId[e.from] && !!byId[e.to] && e.from !== e.to);
    markBackEdges(nodes, live);
    // Longest path over the forward edges, relaxed until nothing moves.
    for (let pass = 0; pass <= nodes.length; pass++) {
        let moved = false;
        live.forEach((e) => {
            if (e.back) {
                return;
            }
            if (byId[e.to].rank < byId[e.from].rank + 1) {
                byId[e.to].rank = byId[e.from].rank + 1;
                moved = true;
            }
        });
        if (!moved) {
            break;
        }
    }
    const all = nodes.slice();
    const links = [];
    live.forEach((e) => {
        e.via = [];
        e.labelAt = undefined;
        if (e.back) {
            return;
        }
        const a = byId[e.from];
        const b = byId[e.to];
        const mid = Math.floor((a.rank + b.rank) / 2);
        let prev = a;
        for (let k = a.rank + 1; k < b.rank; k++) {
            const holds = k === mid && !!e.labelW;
            const across = holds ? (opts.vertical ? e.labelW || 0 : e.labelH || 0) : 6;
            const depth = holds ? (opts.vertical ? e.labelH || 0 : e.labelW || 0) : 6;
            const d = {
                id: '\u0001' + all.length, w: opts.vertical ? across : depth, h: opts.vertical ? depth : across,
                group: a.group === b.group ? a.group : undefined, x: 0, y: 0, rank: k
            };
            all.push(d);
            e.via.push(d);
            if (holds) {
                e.labelAt = d;
            }
            links.push({ from: prev, to: d });
            prev = d;
        }
        links.push({ from: prev, to: b });
    });
    const up = {};
    const down = {};
    links.forEach((l) => {
        (up[l.to.id] = up[l.to.id] || []).push(l.from);
        (down[l.from.id] = down[l.from.id] || []).push(l.to);
    });
    const index = {};
    all.forEach((n, i) => { index[n.id] = i; });
    const ranks = [];
    all.forEach((n) => { (ranks[n.rank] = ranks[n.rank] || []).push(n); });
    for (let i = 0; i < ranks.length; i++) {
        ranks[i] = ranks[i] || [];
    }
    const groupKey = (n) => {
        const g = n.group ? opts.groupOrder.indexOf(n.group) : -1;
        return g < 0 ? opts.groupOrder.length : g;
    };
    const pos = {};
    const setPos = () => { ranks.forEach((rk) => { rk.forEach((n, i) => { pos[n.id] = i; }); }); };
    ranks.forEach((rk) => { rk.sort((a, b) => groupKey(a) - groupKey(b) || index[a.id] - index[b.id]); });
    setPos();
    // Barycentre sweeps, down then up.
    for (let sweep = 0; sweep < 8; sweep++) {
        const downward = sweep % 2 === 0;
        for (let k = 1; k < ranks.length; k++) {
            const rk = ranks[downward ? k : ranks.length - 1 - k];
            const bary = {};
            rk.forEach((n) => {
                const near = (downward ? up[n.id] : down[n.id]) || [];
                bary[n.id] = near.length ? near.reduce((s, m) => s + pos[m.id], 0) / near.length : pos[n.id];
            });
            rk.sort((a, b) => groupKey(a) - groupKey(b) || bary[a.id] - bary[b.id] || index[a.id] - index[b.id]);
            setPos();
        }
    }
    // Place: across = position along a rank, along = the rank's offset.
    const across = (n) => (opts.vertical ? n.w : n.h);
    const depth = (n) => (opts.vertical ? n.h : n.w);
    const centre = {};
    let along = 0;
    ranks.forEach((rk) => {
        const size = rk.reduce((m, n) => Math.max(m, depth(n)), 0);
        // Where each node would like to be: level with what feeds it.
        const want = rk.map((n) => {
            const near = up[n.id] || [];
            return near.length ? near.reduce((s, m) => s + centre[m.id], 0) / near.length : NaN;
        });
        let cursor = 0;
        const start = [];
        rk.forEach((n, i) => {
            const gap = i === 0 ? 0 : (rk[i - 1].group !== n.group ? opts.groupGap : opts.nodeGap);
            const lowest = i === 0 ? -Infinity : cursor + gap;
            const desired = isNaN(want[i]) ? lowest : want[i] - across(n) / 2;
            start[i] = i === 0 && isNaN(want[i]) ? 0 : Math.max(lowest, desired);
            cursor = start[i] + across(n);
        });
        // Shift the rank as a whole so it sits evenly about where it wanted to be.
        const wanted = [];
        rk.forEach((n, i) => { if (!isNaN(want[i])) {
            wanted.push(want[i] - across(n) / 2 - start[i]);
        } });
        const shift = wanted.length ? wanted.reduce((s, v) => s + v, 0) / wanted.length : 0;
        rk.forEach((n, i) => {
            const a = start[i] + shift;
            const d = along + (size - depth(n)) / 2;
            if (opts.vertical) {
                n.x = a;
                n.y = d;
            }
            else {
                n.x = d;
                n.y = a;
            }
            centre[n.id] = a + across(n) / 2;
        });
        along += size + opts.rankGap;
    });
    if (!all.length) {
        return { width: 0, height: 0 };
    }
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    all.forEach((n) => {
        minX = Math.min(minX, n.x);
        minY = Math.min(minY, n.y);
        maxX = Math.max(maxX, n.x + n.w);
        maxY = Math.max(maxY, n.y + n.h);
    });
    all.forEach((n) => { n.x -= minX; n.y -= minY; });
    return { width: maxX - minX, height: maxY - minY };
}
exports.layoutGraph = layoutGraph;
// Depth-first in input order; an edge back to a node still on the path
// closes a cycle and is drawn as a back edge.
function markBackEdges(nodes, edges) {
    const state = {};
    const out = {};
    edges.forEach((e) => { e.back = false; (out[e.from] = out[e.from] || []).push(e); });
    const visit = (id) => {
        state[id] = 1;
        (out[id] || []).forEach((e) => {
            if (state[e.to] === 1) {
                e.back = true;
            }
            else if (!state[e.to]) {
                visit(e.to);
            }
        });
        state[id] = 2;
    };
    // Start from nodes nothing points at, so a cycle breaks at its far end.
    const fed = {};
    edges.forEach((e) => { fed[e.to] = true; });
    nodes.forEach((n) => { if (!fed[n.id] && !state[n.id]) {
        visit(n.id);
    } });
    nodes.forEach((n) => { if (!state[n.id]) {
        visit(n.id);
    } });
}
function f(n) {
    return String(Math.round(n * 10) / 10);
}
// A forward edge: out of one node, through each placeholder it crosses, into
// the next, as curves between ranks and straight runs through placeholders.
function forwardPath(a, b, via, vertical) {
    let cur = vertical ? [a.x + a.w / 2, a.y + a.h] : [a.x + a.w, a.y + a.h / 2];
    let d = 'M' + f(cur[0]) + ',' + f(cur[1]);
    let mid = { x: 0, y: 0 };
    const curveTo = (q) => {
        const m = vertical ? (cur[1] + q[1]) / 2 : (cur[0] + q[0]) / 2;
        const c1 = vertical ? [cur[0], m] : [m, cur[1]];
        const c2 = vertical ? [q[0], m] : [m, q[1]];
        d += ' C' + f(c1[0]) + ',' + f(c1[1]) + ' ' + f(c2[0]) + ',' + f(c2[1]) + ' ' + f(q[0]) + ',' + f(q[1]);
        mid = { x: (cur[0] + 3 * c1[0] + 3 * c2[0] + q[0]) / 8, y: (cur[1] + 3 * c1[1] + 3 * c2[1] + q[1]) / 8 };
        cur = q;
    };
    via.forEach((v) => {
        curveTo(vertical ? [v.x + v.w / 2, v.y] : [v.x, v.y + v.h / 2]);
        cur = vertical ? [v.x + v.w / 2, v.y + v.h] : [v.x + v.w, v.y + v.h / 2];
        d += ' L' + f(cur[0]) + ',' + f(cur[1]);
    });
    curveTo(vertical ? [b.x + b.w / 2, b.y] : [b.x, b.y + b.h / 2]);
    return { d: d, mid: mid };
}
exports.forwardPath = forwardPath;
// A back or same-rank edge: a loop round the outside of the drawing, on the
// near side (`before` is above, or left when vertical), `reach` beyond the
// nodes so its label clears whatever runs between them.
function loopPath(a, b, vertical, reach, before) {
    let p0;
    let p3;
    let p1;
    let p2;
    if (vertical) {
        const ax = before ? a.x : a.x + a.w;
        const bx = before ? b.x : b.x + b.w;
        p0 = [ax, a.y + a.h / 2];
        p3 = [bx, b.y + b.h / 2];
        const out = before ? Math.min(ax, bx) - reach : Math.max(ax, bx) + reach;
        p1 = [out, p0[1]];
        p2 = [out, p3[1]];
    }
    else {
        const ay = before ? a.y : a.y + a.h;
        const by = before ? b.y : b.y + b.h;
        p0 = [a.x + a.w / 2, ay];
        p3 = [b.x + b.w / 2, by];
        const out = before ? Math.min(ay, by) - reach : Math.max(ay, by) + reach;
        p1 = [p0[0], out];
        p2 = [p3[0], out];
    }
    return {
        d: 'M' + f(p0[0]) + ',' + f(p0[1]) + ' C' + f(p1[0]) + ',' + f(p1[1]) + ' ' + f(p2[0]) + ',' + f(p2[1]) + ' ' + f(p3[0]) + ',' + f(p3[1]),
        mid: { x: (p0[0] + 3 * p1[0] + 3 * p2[0] + p3[0]) / 8, y: (p0[1] + 3 * p1[1] + 3 * p2[1] + p3[1]) / 8 }
    };
}
exports.loopPath = loopPath;

};
 defs['JourneyChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderJourney = void 0;
const ChartKit_1 = require("./ChartKit");
// A user journey: one card per step, grouped by stage, each with its
// satisfaction score (1 to 5) and the actors involved.
function renderJourney(data, theme) {
    const sections = (0, ChartKit_1.list)(data && data.sections);
    if (!sections.length) {
        return '';
    }
    let out = '<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:16px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">';
    sections.forEach((s) => {
        out += '<section style="min-width:0">' +
            '<div style="font-size:12px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;color:' + (0, ChartKit_1.esc)(theme.muted) + ';margin-bottom:6px">' + (0, ChartKit_1.esc)(s.name) + '</div>' +
            '<div style="display:flex;flex-direction:column;gap:8px">';
        (0, ChartKit_1.list)(s.tasks).forEach((t) => {
            const score = Math.max(0, Math.min(5, Math.round((0, ChartKit_1.num)(t.score))));
            const colour = score >= 4 ? '#16a34a' : score === 3 ? '#d97706' : '#dc2626';
            out += '<div style="border:1px solid ' + (0, ChartKit_1.esc)(theme.line) + ';border-left:4px solid ' + colour + ';border-radius:8px;padding:8px 10px">' +
                '<div style="display:flex;justify-content:space-between;gap:8px;align-items:baseline">' +
                '<span style="font-weight:600">' + (0, ChartKit_1.esc)(t.label) + '</span>' +
                '<span role="img" aria-label="Score ' + score + ' of 5" title="Score ' + score + ' of 5" style="flex:none;color:' + colour + ';letter-spacing:1px">' + dots(score) + '</span></div>' +
                ((0, ChartKit_1.list)(t.actors).length
                    ? '<div style="margin-top:4px;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, ChartKit_1.list)(t.actors).map((a) => (0, ChartKit_1.esc)((0, ChartKit_1.str)(a))).join(', ') + '</div>'
                    : '') +
                '</div>';
        });
        out += '</div></section>';
    });
    return out + '</div>';
}
exports.renderJourney = renderJourney;
function dots(score) {
    let s = '';
    for (let i = 1; i <= 5; i++) {
        s += i <= score ? '&#9679;' : '&#9675;';
    }
    return s;
}

};
 defs['MindmapChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderMindmap = void 0;
const ChartKit_1 = require("./ChartKit");
const GAP_X = 44;
const GAP_Y = 10;
const LINE = 16;
// A tree read left to right: the root, then each branch in its own colour.
function renderMindmap(data, theme, label) {
    if (!data || !data.root) {
        return '';
    }
    const root = build(data.root, 0, theme.accent);
    const colW = [];
    measure(root, colW);
    const colX = [];
    let x = 2;
    colW.forEach((w, d) => { colX[d] = x; x += w + GAP_X; });
    const height = place(root, 2, colX);
    let edges = '';
    let boxes = '';
    const draw = (b) => {
        b.children.forEach((c) => {
            const x0 = b.x + b.w;
            const y0 = b.y + b.h / 2;
            const x1 = c.x;
            const y1 = c.y + c.h / 2;
            const xm = (x0 + x1) / 2;
            edges += '<path d="M' + (0, ChartKit_1.r)(x0) + ',' + (0, ChartKit_1.r)(y0) + ' C' + (0, ChartKit_1.r)(xm) + ',' + (0, ChartKit_1.r)(y0) + ' ' + (0, ChartKit_1.r)(xm) + ',' + (0, ChartKit_1.r)(y1) + ' ' + (0, ChartKit_1.r)(x1) + ',' + (0, ChartKit_1.r)(y1) + '" fill="none" stroke="' + (0, ChartKit_1.esc)(c.colour) + '" stroke-width="2" stroke-opacity="0.7"/>';
            draw(c);
        });
        const isRoot = b.depth === 0;
        boxes += (0, ChartKit_1.rect)(b.x, b.y, b.w, b.h, 'rx="8" fill="' + (0, ChartKit_1.esc)(isRoot ? b.colour : theme.surface) + '" stroke="' + (0, ChartKit_1.esc)(b.colour) + '" stroke-width="' + (isRoot ? 0 : 1.5) + '"');
        if (!isRoot) {
            boxes += (0, ChartKit_1.rect)(b.x, b.y, b.w, b.h, 'rx="8" fill="' + (0, ChartKit_1.esc)(b.colour) + '" fill-opacity="0.1"');
        }
        boxes += (0, ChartKit_1.svgText)(b.x + b.w / 2, b.y + b.h / 2, b.lines, { size: isRoot ? 14 : 12, weight: isRoot ? 600 : 400, fill: isRoot ? '#ffffff' : theme.text, anchor: 'middle', lineHeight: LINE });
    };
    draw(root);
    return (0, ChartKit_1.svgDoc)(x - GAP_X + 4, height + 4, label, edges + boxes);
}
exports.renderMindmap = renderMindmap;
function build(n, depth, colour) {
    const size = depth === 0 ? 14 : 12;
    const lines = (0, ChartKit_1.wrapText)((0, ChartKit_1.str)(n.text), 200, size, depth === 0);
    const box = {
        lines: lines, w: (0, ChartKit_1.widest)(lines, size, depth === 0) + 24, h: lines.length * LINE + 14,
        depth: depth, colour: colour, x: 0, y: 0, children: []
    };
    box.children = (0, ChartKit_1.list)(n.children).map((c, i) => build(c, depth + 1, depth === 0 ? ChartKit_1.SERIES[i % ChartKit_1.SERIES.length] : colour));
    return box;
}
function measure(b, colW) {
    colW[b.depth] = Math.max(colW[b.depth] || 0, b.w);
    b.children.forEach((c) => measure(c, colW));
}
// Leaves are stacked top to bottom; a parent sits level with the middle of
// its children. Returns the bottom of the subtree.
function place(b, top, colX) {
    b.x = colX[b.depth];
    if (!b.children.length) {
        b.y = top;
        return top + b.h + GAP_Y;
    }
    let y = top;
    b.children.forEach((c) => { y = place(c, y, colX); });
    const first = b.children[0];
    const last = b.children[b.children.length - 1];
    b.y = (first.y + last.y + last.h) / 2 - b.h / 2;
    if (b.y < top) {
        const shift = top - b.y;
        b.y = top;
        shiftTree(b, shift, true);
        y += shift;
    }
    return Math.max(y, b.y + b.h + GAP_Y);
}
function shiftTree(b, dy, skipSelf) {
    if (!skipSelf) {
        b.y += dy;
    }
    b.children.forEach((c) => shiftTree(c, dy, false));
}

};
 defs['NoteNode']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.noteNode = void 0;
const ChartKit_1 = require("./ChartKit");
// A sticky note for state and class diagrams, joined to what it describes by
// a dashed line.
function noteNode(id, text, theme) {
    const lines = (0, ChartKit_1.wrapText)(text, 200, 12);
    const fill = theme.dark ? '#3f2d0a' : '#fef3c7';
    const ink = theme.dark ? '#fde68a' : '#78350f';
    return {
        id: id, w: (0, ChartKit_1.widest)(lines, 12) + 22, h: lines.length * 16 + 16, x: 0, y: 0, rank: 0,
        draw: (b) => (0, ChartKit_1.rect)(b.x, b.y, b.w, b.h, 'rx="4" fill="' + fill + '" stroke="#d97706" stroke-width="1"') +
            (0, ChartKit_1.svgText)(b.x + 11, b.y + b.h / 2, lines, { size: 12, fill: ink, lineHeight: 16 })
    };
}
exports.noteNode = noteNode;

};
 defs['PieChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderPie = void 0;
const ChartKit_1 = require("./ChartKit");
const SIZE = 200;
const OUTER = 92;
const INNER = 58;
// A donut with the total in the middle and every slice in the legend,
// including slices of zero, which the ring cannot show.
function renderPie(data, theme, label) {
    const slices = (0, ChartKit_1.list)(data && data.slices).map((s, i) => ({
        label: (0, ChartKit_1.str)(s.label), value: Math.max(0, (0, ChartKit_1.num)(s.value)), colour: (0, ChartKit_1.colourFor)((0, ChartKit_1.str)(s.label), i)
    }));
    const total = slices.reduce((a, s) => a + s.value, 0);
    const c = SIZE / 2;
    let ring = '';
    if (total <= 0) {
        ring = annulus(c, 0, Math.PI * 2, theme.line);
    }
    else {
        let angle = 0;
        slices.forEach((s) => {
            if (s.value <= 0) {
                return;
            }
            const sweep = (s.value / total) * Math.PI * 2;
            ring += annulus(c, angle, angle + sweep, s.colour, s.label + ': ' + (0, ChartKit_1.fmt)(s.value) + ' (' + pct(s.value, total) + ')');
            angle += sweep;
        });
    }
    const centre = (0, ChartKit_1.svgText)(c, c - 8, [total > 0 ? (0, ChartKit_1.fmt)(total) : '0'], { size: 26, weight: 600, fill: theme.text, anchor: 'middle' }) +
        (0, ChartKit_1.svgText)(c, c + 18, ['total'], { size: 12, fill: theme.muted, anchor: 'middle' });
    const chart = (0, ChartKit_1.svgDoc)(SIZE, SIZE, label, ring + centre);
    const showData = !data || data.showData !== false;
    const legend = slices.map((s) => '<div style="display:flex;align-items:center;gap:8px;padding:3px 0">' +
        '<i style="flex:none;width:11px;height:11px;border-radius:3px;background:' + (0, ChartKit_1.esc)(s.colour) + '"></i>' +
        '<span style="flex:1 1 auto;min-width:0;overflow-wrap:anywhere">' + (0, ChartKit_1.esc)(s.label) + '</span>' +
        (showData ? '<span style="flex:none;font-variant-numeric:tabular-nums">' + (0, ChartKit_1.esc)((0, ChartKit_1.fmt)(s.value)) + '</span>' : '') +
        '<span style="flex:none;width:44px;text-align:right;color:' + (0, ChartKit_1.esc)(theme.muted) + ';font-variant-numeric:tabular-nums">' + (0, ChartKit_1.esc)(pct(s.value, total)) + '</span>' +
        '</div>').join('');
    return '<div style="display:flex;flex-wrap:wrap;align-items:center;gap:16px 28px">' +
        '<div style="flex:none;width:' + SIZE + 'px;max-width:100%">' + chart + '</div>' +
        '<div style="flex:1 1 220px;min-width:0;max-width:340px;font-size:13px">' + legend + '</div>' +
        '</div>';
}
exports.renderPie = renderPie;
function pct(value, total) {
    if (total <= 0) {
        return '0%';
    }
    const p = (value / total) * 100;
    return value > 0 && p < 1 ? '<1%' : Math.round(p) + '%';
}
function point(c, radius, angle) {
    return (0, ChartKit_1.r)(c + radius * Math.sin(angle)) + ',' + (0, ChartKit_1.r)(c - radius * Math.cos(angle));
}
// One slice of the ring, clockwise from twelve o'clock. A full circle is
// drawn as two halves, since an arc cannot start and end at one point.
function annulus(c, a0, a1, colour, tip) {
    if (a1 - a0 >= Math.PI * 2 - 1e-6) {
        return annulus(c, a0, a0 + Math.PI, colour, tip) + annulus(c, a0 + Math.PI, a0 + Math.PI * 2, colour, tip);
    }
    const large = a1 - a0 > Math.PI ? 1 : 0;
    const d = 'M' + point(c, OUTER, a0) + ' A' + OUTER + ',' + OUTER + ' 0 ' + large + ' 1 ' + point(c, OUTER, a1) +
        ' L' + point(c, INNER, a1) + ' A' + INNER + ',' + INNER + ' 0 ' + large + ' 0 ' + point(c, INNER, a0) + ' Z';
    return '<path d="' + d + '" fill="' + (0, ChartKit_1.esc)(colour) + '">' + (tip ? '<title>' + (0, ChartKit_1.esc)(tip) + '</title>' : '') + '</path>';
}

};
 defs['SankeyChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderSankey = void 0;
const ChartKit_1 = require("./ChartKit");
const NODE_W = 12;
const GAP = 12;
const MIN_H = 3;
// Flows between named stages. Each node sits in the column of its longest
// path from a source; its height is the larger of what flows in and out.
function renderSankey(data, theme, label) {
    const nodes = {};
    const order = [];
    const node = (name) => {
        if (!nodes[name]) {
            nodes[name] = { name: name, index: order.length, col: 0, inValue: 0, outValue: 0, x: 0, y: 0, h: 0, inOff: 0, outOff: 0, colour: '' };
            order.push(nodes[name]);
        }
        return nodes[name];
    };
    const links = [];
    (0, ChartKit_1.list)(data && data.links).forEach((l) => {
        const value = (0, ChartKit_1.num)(l.value);
        const s = (0, ChartKit_1.str)(l.source);
        const t = (0, ChartKit_1.str)(l.target);
        if (!s || !t || s === t || value <= 0) {
            return;
        }
        const link = { source: node(s), target: node(t), value: value };
        link.source.outValue += value;
        link.target.inValue += value;
        links.push(link);
    });
    if (!links.length) {
        return '';
    }
    // Longest path from a source; the pass limit stops a cycle looping forever.
    for (let pass = 0; pass < order.length; pass++) {
        let moved = false;
        links.forEach((l) => {
            if (l.target.col < l.source.col + 1) {
                l.target.col = l.source.col + 1;
                moved = true;
            }
        });
        if (!moved) {
            break;
        }
    }
    const cols = [];
    order.forEach((n) => {
        n.colour = (0, ChartKit_1.colourFor)(n.name, n.index);
        (cols[n.col] = cols[n.col] || []).push(n);
    });
    for (let c = 0; c < cols.length; c++) {
        cols[c] = cols[c] || [];
    }
    const height = Math.max(260, cols.reduce((m, c) => Math.max(m, c.length), 0) * 46);
    const scale = Math.min(...cols.filter((c) => c.length > 0).map((c) => {
        const total = c.reduce((a, n) => a + Math.max(n.inValue, n.outValue), 0);
        return (height - GAP * (c.length - 1)) / total;
    }));
    // Each column is followed by room for its widest label, and each node has
    // a slot at least as tall as its label so small nodes' labels never collide.
    let x = 4;
    const colH = [];
    cols.forEach((c, ci) => {
        const labelW = c.reduce((m, n) => Math.max(m, (0, ChartKit_1.widest)(nameLines(n), 12, true), (0, ChartKit_1.widest)([value(n)], 11)), 0);
        c.forEach((n) => { n.x = x; n.h = Math.max(MIN_H, Math.max(n.inValue, n.outValue) * scale); });
        colH[ci] = c.reduce((a, n) => a + slot(n), 0) + GAP * (c.length - 1);
        x += NODE_W + Math.max(80, labelW + 30);
    });
    const fullH = Math.max(height, ...colH);
    cols.forEach((c, ci) => {
        let y = (fullH - colH[ci]) / 2;
        c.forEach((n) => { n.y = y + (slot(n) - n.h) / 2; y += slot(n) + GAP; });
    });
    // Bands leave and enter each node in the order of the node at the far end,
    // which keeps them from crossing more than they must.
    const sorted = links.slice().sort((a, b) => a.target.y - b.target.y || a.source.y - b.source.y);
    let body = '';
    const bandTop = {};
    sorted.forEach((l, i) => {
        const sh = (l.value / Math.max(l.source.outValue, l.source.inValue)) * l.source.h;
        bandTop[i] = l.source.y + l.source.outOff;
        l.source.outOff += sh;
    });
    links.slice().sort((a, b) => a.source.y - b.source.y || a.target.y - b.target.y).forEach((l) => {
        const i = sorted.indexOf(l);
        const sh = (l.value / Math.max(l.source.outValue, l.source.inValue)) * l.source.h;
        const th = (l.value / Math.max(l.target.inValue, l.target.outValue)) * l.target.h;
        const sy = bandTop[i];
        const ty = l.target.y + l.target.inOff;
        l.target.inOff += th;
        const x0 = l.source.x + NODE_W;
        const x1 = l.target.x;
        const xm = (x0 + x1) / 2;
        const d = 'M' + (0, ChartKit_1.r)(x0) + ',' + (0, ChartKit_1.r)(sy) + ' C' + (0, ChartKit_1.r)(xm) + ',' + (0, ChartKit_1.r)(sy) + ' ' + (0, ChartKit_1.r)(xm) + ',' + (0, ChartKit_1.r)(ty) + ' ' + (0, ChartKit_1.r)(x1) + ',' + (0, ChartKit_1.r)(ty) +
            ' L' + (0, ChartKit_1.r)(x1) + ',' + (0, ChartKit_1.r)(ty + th) + ' C' + (0, ChartKit_1.r)(xm) + ',' + (0, ChartKit_1.r)(ty + th) + ' ' + (0, ChartKit_1.r)(xm) + ',' + (0, ChartKit_1.r)(sy + sh) + ' ' + (0, ChartKit_1.r)(x0) + ',' + (0, ChartKit_1.r)(sy + sh) + ' Z';
        body += '<path d="' + d + '" fill="' + (0, ChartKit_1.esc)(l.source.colour) + '" fill-opacity="' + (theme.dark ? '0.45' : '0.3') + '">' +
            '<title>' + (0, ChartKit_1.esc)(l.source.name + ' to ' + l.target.name + ': ' + (0, ChartKit_1.fmt)(l.value)) + '</title></path>';
    });
    order.forEach((n) => {
        const lines = nameLines(n);
        const cy = n.y + n.h / 2;
        body += (0, ChartKit_1.rect)(n.x, n.y, NODE_W, n.h, 'rx="2" fill="' + (0, ChartKit_1.esc)(n.colour) + '"').replace('/>', '><title>' + (0, ChartKit_1.esc)(n.name + ': ' + value(n)) + '</title></rect>');
        body += '<g stroke="' + (0, ChartKit_1.esc)(theme.surface) + '" stroke-width="4" stroke-linejoin="round" paint-order="stroke">' +
            (0, ChartKit_1.svgText)(n.x + NODE_W + 6, cy - 7, lines, { size: 12, weight: 600, fill: theme.text, lineHeight: 14 }) +
            (0, ChartKit_1.svgText)(n.x + NODE_W + 6, cy + (lines.length * 14) / 2, [value(n)], { size: 11, fill: theme.muted }) + '</g>';
    });
    return (0, ChartKit_1.svgDoc)(x, fullH + 4, label, body);
}
exports.renderSankey = renderSankey;
function slot(n) {
    return Math.max(n.h, nameLines(n).length * 14 + 18);
}
function nameLines(n) {
    return (0, ChartKit_1.wrapText)(n.name, 150, 12, true);
}
function value(n) {
    return (0, ChartKit_1.fmt)(Math.max(n.inValue, n.outValue));
}

};
 defs['SequenceChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderSequence = void 0;
const ChartKit_1 = require("./ChartKit");
const BOX_H_LINE = 16;
const TEXT_W = 150;
// Participants across the top with their lifelines, and each message, note
// and block (loop, alt, opt and the like) in order down the page.
function renderSequence(data, theme, label) {
    const actors = (0, ChartKit_1.list)(data && data.participants).map((p) => {
        const lines = (0, ChartKit_1.wrapText)((0, ChartKit_1.str)(p.label) || (0, ChartKit_1.str)(p.id), 100, 12, true);
        return { id: (0, ChartKit_1.str)(p.id), lines: lines, w: Math.max(72, (0, ChartKit_1.widest)(lines, 12, true) + 20), x: 0 };
    });
    const steps = (0, ChartKit_1.list)(data && data.steps);
    const at = {};
    const ensure = (id) => {
        if (at[id] === undefined) {
            const lines = [id];
            actors.push({ id: id, lines: lines, w: Math.max(84, (0, ChartKit_1.widest)(lines, 12, true) + 24), x: 0 });
            at[id] = actors.length - 1;
        }
        return at[id];
    };
    actors.forEach((a, i) => { at[a.id] = i; });
    steps.forEach((s) => {
        if (s.kind === 'message') {
            ensure((0, ChartKit_1.str)(s.from));
            ensure((0, ChartKit_1.str)(s.to));
        }
        if (s.kind === 'note') {
            (0, ChartKit_1.list)(s.over).forEach((o) => { ensure((0, ChartKit_1.str)(o)); });
        }
    });
    if (!actors.length) {
        return '';
    }
    // Space the lifelines so every message's text fits between its ends.
    const gaps = actors.map((a, i) => (i < actors.length - 1 ? Math.max(96, a.w / 2 + actors[i + 1].w / 2 + 16) : 0));
    steps.forEach((s) => {
        const textW = (0, ChartKit_1.widest)((0, ChartKit_1.wrapText)((0, ChartKit_1.str)(s.text), TEXT_W, 12), 12);
        if (s.kind === 'message') {
            const a = at[(0, ChartKit_1.str)(s.from)];
            const b = at[(0, ChartKit_1.str)(s.to)];
            if (a === b) {
                if (a < gaps.length - 1) {
                    gaps[a] = Math.max(gaps[a], textW + 50);
                }
                return;
            }
            const lo = Math.min(a, b);
            const hi = Math.max(a, b);
            let have = 0;
            for (let i = lo; i < hi; i++) {
                have += gaps[i];
            }
            const need = textW + 36;
            if (have < need) {
                for (let i = lo; i < hi; i++) {
                    gaps[i] += (need - have) / (hi - lo);
                }
            }
        }
    });
    let x = actors[0].w / 2 + 8;
    actors.forEach((a, i) => { a.x = x; x += gaps[i]; });
    const right = actors[actors.length - 1].x + actors[actors.length - 1].w / 2 + 8;
    const boxH = actors.reduce((m, a) => Math.max(m, a.lines.length * BOX_H_LINE + 18), 0);
    const arrowId = (0, ChartKit_1.nextId)('seq');
    const openId = (0, ChartKit_1.nextId)('seqo');
    let y = boxH + 24;
    let body = '';
    let frames = '';
    const stack = [];
    let number = 0;
    let extraRight = right;
    steps.forEach((s) => {
        if (s.kind === 'message') {
            const a = actors[at[(0, ChartKit_1.str)(s.from)]];
            const b = actors[at[(0, ChartKit_1.str)(s.to)]];
            const lines = (0, ChartKit_1.wrapText)((0, ChartKit_1.str)(s.text), TEXT_W, 12);
            const textH = lines.length * 15;
            const lineY = y + textH + 6;
            const dash = s.dashed ? ' stroke-dasharray="6 4"' : '';
            if (a === b) {
                const loopX = a.x + 44;
                body += '<path d="M' + (0, ChartKit_1.r)(a.x) + ',' + (0, ChartKit_1.r)(lineY) + ' H' + (0, ChartKit_1.r)(loopX) + ' V' + (0, ChartKit_1.r)(lineY + 18) + ' H' + (0, ChartKit_1.r)(a.x + 3) + '" fill="none" stroke="' + (0, ChartKit_1.esc)(theme.text) + '" stroke-width="1.4"' + dash + ' marker-end="url(#' + arrowId + ')"/>';
                body += (0, ChartKit_1.svgText)(a.x + 8, y + textH / 2, lines, { size: 12, fill: theme.text, lineHeight: 15 });
                extraRight = Math.max(extraRight, a.x + 52 + (0, ChartKit_1.widest)(lines, 12));
                y = lineY + 30;
            }
            else {
                const dir = b.x > a.x ? 1 : -1;
                body += '<line x1="' + (0, ChartKit_1.r)(a.x) + '" y1="' + (0, ChartKit_1.r)(lineY) + '" x2="' + (0, ChartKit_1.r)(b.x - dir * 2) + '" y2="' + (0, ChartKit_1.r)(lineY) + '" stroke="' + (0, ChartKit_1.esc)(theme.text) + '" stroke-width="1.4"' + dash +
                    ' marker-end="url(#' + (s.dashed ? openId : arrowId) + ')"/>';
                body += (0, ChartKit_1.svgText)((a.x + b.x) / 2, y + textH / 2, lines, { size: 12, fill: theme.text, anchor: 'middle', lineHeight: 15 });
                y = lineY + 16;
            }
            if (data.autonumber) {
                number++;
                body += '<circle cx="' + (0, ChartKit_1.r)(a.x) + '" cy="' + (0, ChartKit_1.r)(lineY) + '" r="9" fill="' + (0, ChartKit_1.esc)(theme.accent) + '"/>' +
                    (0, ChartKit_1.svgText)(a.x, lineY, [String(number)], { size: 10, weight: 600, fill: '#ffffff', anchor: 'middle' });
            }
            return;
        }
        if (s.kind === 'note') {
            const over = (0, ChartKit_1.list)(s.over).map((o) => at[(0, ChartKit_1.str)(o)]).filter((i) => i !== undefined);
            if (!over.length) {
                return;
            }
            const lines = (0, ChartKit_1.wrapText)((0, ChartKit_1.str)(s.text), 200, 12);
            const w = (0, ChartKit_1.widest)(lines, 12) + 20;
            const h = lines.length * 15 + 12;
            const xs = over.map((i) => actors[i].x);
            let x0;
            let x1;
            if (s.position === 'left of') {
                x1 = xs[0] - 10;
                x0 = x1 - w;
            }
            else if (s.position === 'right of') {
                x0 = xs[0] + 10;
                x1 = x0 + w;
            }
            else {
                const lo = Math.min(...xs);
                const hi = Math.max(...xs);
                const span = Math.max(w, hi - lo + 40);
                x0 = (lo + hi) / 2 - span / 2;
                x1 = x0 + span;
            }
            extraRight = Math.max(extraRight, x1);
            body += (0, ChartKit_1.rect)(x0, y, x1 - x0, h, 'rx="4" fill="' + (theme.dark ? '#3f2d0a' : '#fef3c7') + '" stroke="#d97706"') +
                (0, ChartKit_1.svgText)(x0 + (x1 - x0) / 2, y + h / 2, lines, { size: 12, fill: theme.dark ? '#fde68a' : '#78350f', anchor: 'middle', lineHeight: 15 });
            y += h + 14;
            return;
        }
        if (s.kind === 'block') {
            const kind = (0, ChartKit_1.str)(s.block);
            if ((kind === 'else' || kind === 'and') && stack.length) {
                stack[stack.length - 1].dividers.push({ y: y, text: (0, ChartKit_1.str)(s.text) });
                y += 24;
                return;
            }
            stack.push({ kind: kind, text: (0, ChartKit_1.str)(s.text), top: y, depth: stack.length, dividers: [] });
            y += 30;
            return;
        }
        if (s.kind === 'end' && stack.length) {
            const f = stack.pop();
            frames += frame(f, y, actors, theme);
            y += 14;
        }
    });
    while (stack.length) {
        frames += frame(stack.pop(), y, actors, theme);
        y += 14;
    }
    let lifelines = '';
    let heads = '';
    actors.forEach((a) => {
        lifelines += '<line x1="' + (0, ChartKit_1.r)(a.x) + '" y1="' + boxH + '" x2="' + (0, ChartKit_1.r)(a.x) + '" y2="' + (0, ChartKit_1.r)(y) + '" stroke="' + (0, ChartKit_1.esc)(theme.line) + '" stroke-width="1.5" stroke-dasharray="4 4"/>';
        heads += (0, ChartKit_1.rect)(a.x - a.w / 2, 0, a.w, boxH, 'rx="8" fill="' + (0, ChartKit_1.esc)(theme.surface) + '" stroke="' + (0, ChartKit_1.esc)(theme.accent) + '" stroke-width="1.5"') +
            (0, ChartKit_1.rect)(a.x - a.w / 2, 0, a.w, boxH, 'rx="8" fill="' + (0, ChartKit_1.esc)(theme.accent) + '" fill-opacity="0.08"') +
            (0, ChartKit_1.svgText)(a.x, boxH / 2, a.lines, { size: 12, weight: 600, fill: theme.text, anchor: 'middle', lineHeight: BOX_H_LINE });
    });
    const defs = '<defs>' + (0, ChartKit_1.marker)(arrowId, 'arrow', theme.text, theme.surface) +
        '<marker id="' + openId + '" viewBox="0 0 12 12" refX="11" refY="6" markerWidth="10" markerHeight="10" orient="auto" markerUnits="userSpaceOnUse">' +
        '<path d="M1,1 L11,6 L1,11" fill="none" stroke="' + (0, ChartKit_1.esc)(theme.text) + '" stroke-width="1.4"/></marker></defs>';
    return (0, ChartKit_1.svgDoc)(Math.max(right, extraRight) + 30, y + 6, label, defs + frames + lifelines + body + heads);
}
exports.renderSequence = renderSequence;
function frame(f, bottom, actors, theme) {
    const inset = f.depth * 8;
    const x0 = actors[0].x - actors[0].w / 2 - 6 + inset;
    const x1 = actors[actors.length - 1].x + actors[actors.length - 1].w / 2 + 6 - inset;
    const tag = f.kind + (f.text ? ' [' + f.text + ']' : '');
    const tagW = (0, ChartKit_1.textWidth)(tag, 11, true) + 16;
    let out = (0, ChartKit_1.rect)(x0, f.top, x1 - x0, bottom - f.top + 4, 'rx="4" fill="none" stroke="' + (0, ChartKit_1.esc)(theme.muted) + '" stroke-width="1.2"') +
        (0, ChartKit_1.rect)(x0, f.top, tagW, 20, 'fill="' + (0, ChartKit_1.esc)(theme.muted) + '" fill-opacity="0.15"') +
        (0, ChartKit_1.svgText)(x0 + 8, f.top + 10, [tag], { size: 11, weight: 600, fill: theme.text });
    f.dividers.forEach((d) => {
        out += '<line x1="' + (0, ChartKit_1.r)(x0) + '" y1="' + (0, ChartKit_1.r)(d.y + 4) + '" x2="' + (0, ChartKit_1.r)(x1) + '" y2="' + (0, ChartKit_1.r)(d.y + 4) + '" stroke="' + (0, ChartKit_1.esc)(theme.muted) + '" stroke-dasharray="5 4"/>' +
            (d.text ? (0, ChartKit_1.svgText)(x0 + 8, d.y + 15, ['[' + d.text + ']'], { size: 11, fill: theme.muted }) : '');
    });
    return out;
}

};
 defs['StateChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderState = void 0;
const ChartKit_1 = require("./ChartKit");
const GraphDraw_1 = require("./GraphDraw");
const NoteNode_1 = require("./NoteNode");
const START = '__start';
const END = '__end';
// States and the transitions between them, top to bottom. A composite state
// is one box listing its substates (the transitions that only say "one of
// these" are folded into that list); [*] is the start dot or the end ring.
function renderState(data, theme, label) {
    const states = (0, ChartKit_1.list)(data && data.states);
    const transitions = (0, ChartKit_1.list)(data && data.transitions);
    const parentOf = {};
    states.forEach((s) => { parentOf[(0, ChartKit_1.str)(s.id)] = (0, ChartKit_1.str)(s.parent) || undefined; });
    const top = (id) => {
        let cur = id;
        for (let guard = 0; parentOf[cur] && guard < 20; guard++) {
            cur = parentOf[cur];
        }
        return cur;
    };
    const children = {};
    states.forEach((s) => {
        const p = parentOf[(0, ChartKit_1.str)(s.id)];
        if (p) {
            (children[p] = children[p] || []).push((0, ChartKit_1.str)(s.label) || (0, ChartKit_1.str)(s.id));
        }
    });
    // Inner transitions between substates are listed in the composite's box.
    transitions.forEach((t) => {
        if (t.parent && t.from !== '[*]' && t.to !== '[*]') {
            (children[t.parent] = children[t.parent] || []).push(t.from + ' to ' + t.to + (t.label ? ': ' + t.label : ''));
        }
    });
    const nodes = [];
    const seen = {};
    const add = (id) => {
        if (seen[id]) {
            return;
        }
        seen[id] = true;
        if (id === START || id === END) {
            nodes.push({ id: id, w: 20, h: 20, x: 0, y: 0, rank: 0, draw: (b) => pseudo(b, id === END, theme) });
            return;
        }
        const s = states.filter((x) => (0, ChartKit_1.str)(x.id) === id);
        const name = s.length ? (0, ChartKit_1.str)(s[0].label) || id : id;
        const inner = children[id] || [];
        const nameLines = (0, ChartKit_1.wrapText)(name, 200, 13, true);
        const innerLines = inner.length ? (0, ChartKit_1.wrapText)(inner.join('\n'), 220, 12) : [];
        const w = Math.max((0, ChartKit_1.widest)(nameLines, 13, true), (0, ChartKit_1.widest)(innerLines, 12)) + 28;
        const h = nameLines.length * 17 + 18 + (innerLines.length ? innerLines.length * 16 + 12 : 0);
        nodes.push({ id: id, w: w, h: h, x: 0, y: 0, rank: 0, draw: (b) => stateBox(b, nameLines, innerLines, theme) });
    };
    const edges = [];
    transitions.forEach((t) => {
        if (t.parent) {
            return;
        }
        const from = t.from === '[*]' ? START : top(t.from);
        const to = t.to === '[*]' ? END : top(t.to);
        add(from);
        add(to);
        edges.push({ from: from, to: to, label: (0, ChartKit_1.str)(t.label) || undefined, end: 'arrow' });
    });
    states.forEach((s) => { if (!parentOf[(0, ChartKit_1.str)(s.id)]) {
        add((0, ChartKit_1.str)(s.id));
    } });
    (0, ChartKit_1.list)(data && data.notes).forEach((n, i) => {
        const id = '__note' + i;
        nodes.push((0, NoteNode_1.noteNode)(id, (0, ChartKit_1.str)(n.text), theme));
        edges.push({ from: top((0, ChartKit_1.str)(n.state)), to: id, dashed: true });
    });
    return (0, GraphDraw_1.drawGraph)(nodes, edges, [], true, theme, label);
}
exports.renderState = renderState;
function pseudo(b, end, theme) {
    const cx = b.x + b.w / 2;
    const cy = b.y + b.h / 2;
    return end
        ? '<circle cx="' + (0, ChartKit_1.r)(cx) + '" cy="' + (0, ChartKit_1.r)(cy) + '" r="9" fill="none" stroke="' + (0, ChartKit_1.esc)(theme.text) + '" stroke-width="1.5"/>' +
            '<circle cx="' + (0, ChartKit_1.r)(cx) + '" cy="' + (0, ChartKit_1.r)(cy) + '" r="5" fill="' + (0, ChartKit_1.esc)(theme.text) + '"/>'
        : '<circle cx="' + (0, ChartKit_1.r)(cx) + '" cy="' + (0, ChartKit_1.r)(cy) + '" r="8" fill="' + (0, ChartKit_1.esc)(theme.text) + '"/>';
}
function stateBox(b, nameLines, innerLines, theme) {
    const nameH = nameLines.length * 17 + 18;
    let out = (0, ChartKit_1.rect)(b.x, b.y, b.w, b.h, 'rx="12" fill="' + (0, ChartKit_1.esc)(theme.surface) + '" stroke="' + (0, ChartKit_1.esc)(theme.accent) + '" stroke-width="1.5"') +
        (0, ChartKit_1.rect)(b.x, b.y, b.w, b.h, 'rx="12" fill="' + (0, ChartKit_1.esc)(theme.accent) + '" fill-opacity="0.07"') +
        (0, ChartKit_1.svgText)(b.x + b.w / 2, b.y + nameH / 2, nameLines, { size: 13, weight: 600, fill: theme.text, anchor: 'middle', lineHeight: 17 });
    if (innerLines.length) {
        out += '<line x1="' + (0, ChartKit_1.r)(b.x) + '" y1="' + (0, ChartKit_1.r)(b.y + nameH) + '" x2="' + (0, ChartKit_1.r)(b.x + b.w) + '" y2="' + (0, ChartKit_1.r)(b.y + nameH) + '" stroke="' + (0, ChartKit_1.esc)(theme.line) + '"/>' +
            (0, ChartKit_1.svgText)(b.x + 14, b.y + nameH + (b.h - nameH) / 2, innerLines, { size: 12, fill: theme.muted, lineHeight: 16 });
    }
    return out;
}

};
 defs['TimelineChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderTimeline = void 0;
const ChartKit_1 = require("./ChartKit");
// A vertical timeline: each period's label beside a dot on a rail, with its
// events listed. Section headings, when the timeline has them, sit on the rail.
function renderTimeline(data, theme) {
    const periods = (0, ChartKit_1.list)(data && data.periods);
    if (!periods.length) {
        return '';
    }
    let lastSection = '';
    let out = '<ol style="list-style:none;margin:0;padding:0;font-size:14px;color:' + (0, ChartKit_1.esc)(theme.text) + '">';
    periods.forEach((p, i) => {
        const section = (0, ChartKit_1.str)(p.section);
        if (section && section !== lastSection) {
            out += '<li style="margin:' + (i ? '14px' : '0') + ' 0 6px;font-size:12px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, ChartKit_1.esc)(section) + '</li>';
            lastSection = section;
        }
        const last = i === periods.length - 1;
        out += '<li style="display:flex;gap:14px;align-items:stretch">' +
            '<div style="flex:none;width:112px;text-align:right;font-weight:600;padding:1px 0 14px;font-variant-numeric:tabular-nums">' + (0, ChartKit_1.esc)(p.label) + '</div>' +
            '<div style="flex:none;position:relative;width:14px">' +
            '<span style="position:absolute;left:3px;top:5px;width:8px;height:8px;border-radius:50%;background:' + (0, ChartKit_1.esc)(theme.accent) + '"></span>' +
            (last ? '' : '<span style="position:absolute;left:6px;top:15px;bottom:-4px;width:2px;background:' + (0, ChartKit_1.esc)(theme.line) + '"></span>') +
            '</div>' +
            '<ul style="flex:1 1 auto;min-width:0;margin:0;padding:0 0 14px 0;list-style:none">' +
            (0, ChartKit_1.list)(p.events).map((e) => '<li style="padding:1px 0">' + (0, ChartKit_1.esc)((0, ChartKit_1.str)(e)) + '</li>').join('') +
            '</ul></li>';
    });
    return out + '</ol>';
}
exports.renderTimeline = renderTimeline;

};
 defs['XyChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderXy = void 0;
const ChartKit_1 = require("./ChartKit");
const FONT_SIZE = 12;
// Bars and lines over shared categories. Bars-only charts whose labels do not
// fit under their columns are drawn as horizontal bars instead.
function renderXy(data, theme, label) {
    const labels = (0, ChartKit_1.list)(data && data.xAxis && data.xAxis.labels).map(ChartKit_1.str);
    const series = (0, ChartKit_1.list)(data && data.series).map((s, i) => ({
        kind: (0, ChartKit_1.str)(s.kind) === 'line' ? 'line' : 'bar',
        name: (0, ChartKit_1.str)(s.name) || 'Series ' + (i + 1),
        values: (0, ChartKit_1.list)(s.values).map(ChartKit_1.num),
        colour: ChartKit_1.SERIES[i % ChartKit_1.SERIES.length]
    }));
    const count = Math.max(labels.length, series.reduce((m, s) => Math.max(m, s.values.length), 0));
    while (labels.length < count) {
        labels.push(String(labels.length + 1));
    }
    if (!count || !series.length) {
        return '';
    }
    const values = [];
    series.forEach((s) => { s.values.forEach((v) => { values.push(v); }); });
    const y = (data && data.yAxis) || {};
    const lo = Math.min((0, ChartKit_1.isNil)(y.min) ? 0 : (0, ChartKit_1.num)(y.min), Math.min(...values.concat([0])));
    const hi = Math.max((0, ChartKit_1.isNil)(y.max) ? 0 : (0, ChartKit_1.num)(y.max), Math.max(...values.concat([0])));
    const whole = values.every((v) => Math.round(v) === v);
    const ticks = (0, ChartKit_1.niceTicks)(lo, hi, 5, whole);
    const axis = { lo: ticks[0], hi: ticks[ticks.length - 1], ticks: ticks };
    const plotW = Math.min(680, Math.max(360, count * 56));
    const band = plotW / count;
    const barsOnly = series.every((s) => s.kind === 'bar');
    const longest = (0, ChartKit_1.widest)(labels, FONT_SIZE);
    const svg = barsOnly && longest > band - 6
        ? horizontal(labels, series, axis, theme, label, (0, ChartKit_1.str)(y.title))
        : vertical(labels, series, axis, theme, label, (0, ChartKit_1.str)(y.title), (0, ChartKit_1.str)(data.xAxis && data.xAxis.title), plotW, band);
    const legend = series.length > 1
        ? series.map((s) => ({ label: s.name, colour: s.colour }))
        : [];
    return svg + (0, ChartKit_1.legendHtml)(legend, theme);
}
exports.renderXy = renderXy;
function vertical(labels, series, axis, theme, label, yTitle, xTitle, plotW, band) {
    const plotH = 240;
    const tickW = (0, ChartKit_1.widest)(axis.ticks.map(ChartKit_1.fmt), 11);
    const left = tickW + 14 + (yTitle ? 22 : 0);
    const wrapped = labels.map((l) => (0, ChartKit_1.wrapText)(l, band - 6, FONT_SIZE));
    const labelLines = wrapped.reduce((m, w) => Math.max(m, w.length), 1);
    const top = 26;
    const bottom = 12 + labelLines * 15 + (xTitle ? 22 : 0);
    const scale = (v) => top + plotH - ((v - axis.lo) / (axis.hi - axis.lo)) * plotH;
    let body = grid(axis, left, plotW, scale, theme);
    const bars = series.filter((s) => s.kind === 'bar');
    const group = band * (bars.length > 1 ? 0.8 : 0.62);
    const barW = bars.length ? group / bars.length : 0;
    const showValues = labels.length * Math.max(1, bars.length) <= 36;
    const zero = scale(Math.max(axis.lo, Math.min(axis.hi, 0)));
    bars.forEach((s, si) => {
        s.values.forEach((v, i) => {
            const x = left + band * i + (band - group) / 2 + barW * si;
            const yv = scale(v);
            body += (0, ChartKit_1.rect)(x + 1, Math.min(yv, zero), barW - 2, Math.abs(zero - yv), 'rx="3" fill="' + (0, ChartKit_1.esc)(s.colour) + '"')
                .replace('/>', '><title>' + (0, ChartKit_1.esc)(labels[i] + (bars.length > 1 ? ' (' + s.name + ')' : '') + ': ' + (0, ChartKit_1.fmt)(v)) + '</title></rect>');
            if (showValues) {
                body += (0, ChartKit_1.svgText)(x + barW / 2, Math.min(yv, zero) - 8, [(0, ChartKit_1.fmt)(v)], { size: 10.5, fill: theme.muted, anchor: 'middle' });
            }
        });
    });
    series.filter((s) => s.kind === 'line').forEach((s) => {
        const pts = s.values.map((v, i) => (0, ChartKit_1.r)(left + band * i + band / 2) + ',' + (0, ChartKit_1.r)(scale(v)));
        body += '<polyline points="' + pts.join(' ') + '" fill="none" stroke="' + (0, ChartKit_1.esc)(s.colour) + '" stroke-width="2.5" stroke-linejoin="round"/>';
        s.values.forEach((v, i) => {
            body += '<circle cx="' + (0, ChartKit_1.r)(left + band * i + band / 2) + '" cy="' + (0, ChartKit_1.r)(scale(v)) + '" r="4" fill="' + (0, ChartKit_1.esc)(s.colour) + '">' +
                '<title>' + (0, ChartKit_1.esc)(labels[i] + ' (' + s.name + '): ' + (0, ChartKit_1.fmt)(v)) + '</title></circle>';
        });
    });
    wrapped.forEach((lines, i) => {
        body += (0, ChartKit_1.svgText)(left + band * i + band / 2, top + plotH + 10 + (lines.length * 15) / 2, lines, { size: FONT_SIZE, fill: theme.text, anchor: 'middle', lineHeight: 15 });
    });
    if (yTitle) {
        body += '<g transform="translate(12,' + (0, ChartKit_1.r)(top + plotH / 2) + ') rotate(-90)">' +
            (0, ChartKit_1.svgText)(0, 0, [yTitle], { size: FONT_SIZE, fill: theme.muted, anchor: 'middle' }) + '</g>';
    }
    if (xTitle) {
        body += (0, ChartKit_1.svgText)(left + plotW / 2, top + plotH + bottom - 10, [xTitle], { size: FONT_SIZE, fill: theme.muted, anchor: 'middle' });
    }
    return (0, ChartKit_1.svgDoc)(left + plotW + 8, top + plotH + bottom, label, body);
}
function horizontal(labels, series, axis, theme, label, xTitle) {
    const labelW = Math.min(220, (0, ChartKit_1.widest)(labels, FONT_SIZE));
    const left = labelW + 16;
    const plotW = 440;
    const barH = series.length > 1 ? 14 : 18;
    // Every label is shown whole: rows grow to fit the longest wrapped name.
    const wrapped = labels.map((l) => (0, ChartKit_1.wrapText)(l, labelW, FONT_SIZE));
    const maxLines = wrapped.reduce((m, w) => Math.max(m, w.length), 1);
    const rowH = Math.max(barH * series.length + 12, maxLines * 14 + 8);
    const top = 8;
    const plotH = rowH * labels.length;
    const valueW = (0, ChartKit_1.widest)(axis.ticks.map(ChartKit_1.fmt), 11) + 12;
    const bottom = 26 + (xTitle ? 20 : 0);
    const scale = (v) => left + ((v - axis.lo) / (axis.hi - axis.lo)) * plotW;
    const zero = scale(Math.max(axis.lo, Math.min(axis.hi, 0)));
    let body = '';
    axis.ticks.forEach((t) => {
        const x = scale(t);
        body += '<line x1="' + (0, ChartKit_1.r)(x) + '" y1="' + top + '" x2="' + (0, ChartKit_1.r)(x) + '" y2="' + (0, ChartKit_1.r)(top + plotH) + '" stroke="' + (0, ChartKit_1.esc)(theme.line) + '"/>';
        body += (0, ChartKit_1.svgText)(x, top + plotH + 12, [(0, ChartKit_1.fmt)(t)], { size: 11, fill: theme.muted, anchor: 'middle' });
    });
    labels.forEach((l, i) => {
        const y0 = top + rowH * i + (rowH - barH * series.length) / 2;
        body += (0, ChartKit_1.svgText)(left - 10, y0 + (barH * series.length) / 2, wrapped[i], { size: FONT_SIZE, fill: theme.text, anchor: 'end', lineHeight: 14 });
        series.forEach((s, si) => {
            const v = i < s.values.length ? s.values[i] : 0;
            const x = scale(v);
            const y = y0 + barH * si;
            body += (0, ChartKit_1.rect)(Math.min(x, zero), y + 1, Math.abs(x - zero), barH - 2, 'rx="3" fill="' + (0, ChartKit_1.esc)(s.colour) + '"')
                .replace('/>', '><title>' + (0, ChartKit_1.esc)(l + (series.length > 1 ? ' (' + s.name + ')' : '') + ': ' + (0, ChartKit_1.fmt)(v)) + '</title></rect>');
            body += (0, ChartKit_1.svgText)(Math.max(x, zero) + 6, y + barH / 2, [(0, ChartKit_1.fmt)(v)], { size: 11, fill: theme.muted });
        });
    });
    if (xTitle) {
        body += (0, ChartKit_1.svgText)(left + plotW / 2, top + plotH + 32, [xTitle], { size: FONT_SIZE, fill: theme.muted, anchor: 'middle' });
    }
    return (0, ChartKit_1.svgDoc)(left + plotW + valueW + (0, ChartKit_1.textWidth)('0', 11), top + plotH + bottom, label, body);
}
function grid(axis, left, plotW, scale, theme) {
    let out = '';
    axis.ticks.forEach((t) => {
        const y = scale(t);
        out += '<line x1="' + (0, ChartKit_1.r)(left) + '" y1="' + (0, ChartKit_1.r)(y) + '" x2="' + (0, ChartKit_1.r)(left + plotW) + '" y2="' + (0, ChartKit_1.r)(y) + '" stroke="' + (0, ChartKit_1.esc)(theme.line) + '"/>';
        out += (0, ChartKit_1.svgText)(left - 8, y, [(0, ChartKit_1.fmt)(t)], { size: 11, fill: theme.muted, anchor: 'end' });
    });
    return out;
}

};
 defs['renderChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderChart = void 0;
const ChartKit_1 = require("./ChartKit");
const PieChart_1 = require("./PieChart");
const XyChart_1 = require("./XyChart");
const SankeyChart_1 = require("./SankeyChart");
const TimelineChart_1 = require("./TimelineChart");
const GanttChart_1 = require("./GanttChart");
const MindmapChart_1 = require("./MindmapChart");
const FlowChart_1 = require("./FlowChart");
const StateChart_1 = require("./StateChart");
const ClassChart_1 = require("./ClassChart");
const SequenceChart_1 = require("./SequenceChart");
const JourneyChart_1 = require("./JourneyChart");
// The markup for one chart block: its title, then the chart drawn from its
// data. A kind this web part does not draw, or data it cannot read, shows
// the chart's Mermaid source (when it has one) rather than nothing.
function renderChart(chart, theme) {
    if (!chart || !(0, ChartKit_1.str)(chart.kind)) {
        return wrap('', note('This web part draws a chart from the iSOC Blueprint. The Blueprint publisher supplies its data.', theme), theme);
    }
    const title = (0, ChartKit_1.str)(chart.title);
    const label = title || describe(chart.kind);
    let body = '';
    try {
        body = draw(chart, theme, label);
    }
    catch (_a) {
        body = '';
    }
    if (!body) {
        body = chart.source
            ? '<pre style="margin:0;padding:12px;border:1px solid ' + (0, ChartKit_1.esc)(theme.line) + ';border-radius:8px;overflow:auto;font-size:12px;white-space:pre">' + (0, ChartKit_1.esc)(chart.source) + '</pre>'
            : note('No data to chart.', theme);
    }
    return wrap(title, body, theme);
}
exports.renderChart = renderChart;
function draw(chart, theme, label) {
    const data = chart.data;
    switch ((0, ChartKit_1.str)(chart.kind)) {
        case 'pie': return (0, PieChart_1.renderPie)(data, theme, label);
        case 'xy': return (0, XyChart_1.renderXy)(data, theme, label);
        case 'sankey': return (0, SankeyChart_1.renderSankey)(data, theme, label);
        case 'timeline': return (0, TimelineChart_1.renderTimeline)(data, theme);
        case 'gantt': return (0, GanttChart_1.renderGantt)(data, theme, label);
        case 'mindmap': return (0, MindmapChart_1.renderMindmap)(data, theme, label);
        case 'flowchart': return (0, FlowChart_1.renderFlowchart)(data, theme, label);
        case 'state': return (0, StateChart_1.renderState)(data, theme, label);
        case 'class': return (0, ClassChart_1.renderClass)(data, theme, label);
        case 'sequence': return (0, SequenceChart_1.renderSequence)(data, theme, label);
        case 'journey': return (0, JourneyChart_1.renderJourney)(data, theme);
        default: return '';
    }
}
function describe(kind) {
    const names = {
        pie: 'Pie chart', xy: 'Bar chart', sankey: 'Flow diagram', timeline: 'Timeline', gantt: 'Schedule',
        mindmap: 'Mind map', flowchart: 'Diagram', state: 'State diagram', class: 'Class diagram',
        sequence: 'Sequence diagram', journey: 'Journey'
    };
    return names[kind] || 'Chart';
}
function note(text, theme) {
    return '<p style="margin:0;color:' + (0, ChartKit_1.esc)(theme.muted) + ';font-style:italic">' + (0, ChartKit_1.esc)(text) + '</p>';
}
// Wide diagrams scroll sideways on a narrow screen rather than shrinking
// their text out of reach.
function wrap(title, body, theme) {
    return '<figure style="margin:0;font-family:' + (0, ChartKit_1.esc)(ChartKit_1.FONT) + ';color:' + (0, ChartKit_1.esc)(theme.text) + '">' +
        (title ? '<figcaption style="font-size:15px;font-weight:600;margin:0 0 12px">' + (0, ChartKit_1.esc)(title) + '</figcaption>' : '') +
        '<div style="overflow-x:auto;-webkit-overflow-scrolling:touch">' + body + '</div>' +
        '</figure>';
}

};
 var cache={};
 function req(n){ n=n.replace(/^\.\//,'').replace(/\.js$/,''); if(cache[n]) return cache[n].exports; if(!defs[n]) throw new Error('No chart module '+n); var m={exports:{}}; cache[n]=m; defs[n](m,m.exports,req); return m.exports; }
 var kit=req('ChartKit'), rc=req('renderChart');
 window.SacCharts={ renderChart: rc.renderChart, setTextMeasurer: kit.setTextMeasurer, FONT: kit.FONT };
})();
