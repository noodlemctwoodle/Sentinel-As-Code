/* dashboard-charts.js: the chart web part's renderers (Modules/iSOCBlueprint/WebParts/src/webparts/isocBlueprintChart/charts)
   bundled for the SharePoint dashboard by Modules/iSOCBlueprint/WebParts/Build-DashboardCharts.ps1. Do not edit;
   regenerate after changing the chart sources.
   sources-sha256: 25fe0935d3c121703e7c5ef58a31e02a207b604d3263a4e9c1cc287ecae78aa8 */
(function(){
'use strict';
 var defs={};
 defs['AccessChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderAccess = void 0;
const ChartKit_1 = require("./ChartKit");
const Visual_1 = require("./Visual");
// Who holds which role at workspace scope: the roles in bands (broad
// roles first, then the Microsoft Sentinel roles, then Log Analytics and
// monitoring, then the rest), each role with how many users, groups and
// service principals hold it. A band a fired finding speaks to carries it.
const TONE = { bad: Visual_1.BAD, ok: Visual_1.OK, info: Visual_1.INFO, neutral: Visual_1.NEUTRAL };
const USER = '#2563eb';
const GROUP = '#7c3aed';
const SP = '#0d9488';
function renderAccess(data, theme) {
    const bands = (0, ChartKit_1.list)(data && data.bands).filter((b) => (0, ChartKit_1.list)(b.roles).length > 0);
    if (!bands.length) {
        return '';
    }
    const max = Math.max(1, ...bands.map((b) => Math.max(...(0, ChartKit_1.list)(b.roles).map(total))));
    const key = '<div style="display:flex;flex-wrap:wrap;gap:14px;font-size:12px;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' +
        [['Users', USER], ['Groups', GROUP], ['Service principals', SP]].map((k) => '<span style="display:inline-flex;align-items:center;gap:6px"><span style="width:10px;height:10px;border-radius:3px;background:' + k[1] + '"></span>' + k[0] + '</span>').join('') + '</div>';
    return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' + key +
        '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(380px,1fr));gap:12px">' +
        bands.map((b) => band(b, max, theme)).join('') + '</div></div>';
}
exports.renderAccess = renderAccess;
function total(r) {
    return (0, ChartKit_1.num)(r.users) + (0, ChartKit_1.num)(r.groups) + (0, ChartKit_1.num)(r.servicePrincipals);
}
function band(b, max, theme) {
    const colour = TONE[(0, ChartKit_1.str)(b.tone)] || Visual_1.NEUTRAL;
    const roles = (0, ChartKit_1.list)(b.roles);
    const sum = roles.reduce((a, r) => a + total(r), 0);
    const findings = (0, ChartKit_1.list)(b.findings).map((f) => (0, Visual_1.pill)((0, ChartKit_1.str)(f), Visual_1.BAD)).join(' ');
    const head = '<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap">' +
        '<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">' + (0, Visual_1.eyebrow)((0, ChartKit_1.str)(b.name), theme, colour) + findings + '</div>' +
        '<span style="font-size:12px;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, Visual_1.count)(sum) + ' assignment' + (sum === 1 ? '' : 's') + '</span></div>';
    const rows = roles.map((r) => {
        const parts = [
            { label: 'Users', value: (0, ChartKit_1.num)(r.users), colour: USER },
            { label: 'Groups', value: (0, ChartKit_1.num)(r.groups), colour: GROUP },
            { label: 'Service principals', value: (0, ChartKit_1.num)(r.servicePrincipals), colour: SP }
        ];
        const t = total(r);
        const detail = parts.filter((p) => p.value > 0).map((p) => (0, Visual_1.count)(p.value) + ' ' + p.label.toLowerCase()).join(', ');
        return '<div style="display:grid;grid-template-columns:minmax(150px,1.8fr) minmax(80px,1.3fr) 34px;gap:10px;align-items:center;padding:5px 0" title="' + (0, ChartKit_1.esc)((0, ChartKit_1.str)(r.role) + ': ' + detail) + '">' +
            '<span style="font-size:12.5px;font-weight:650;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + (0, ChartKit_1.esc)(r.role) + '</span>' +
            '<div style="width:' + (t / max * 100).toFixed(1) + '%;min-width:6px">' + (0, Visual_1.meter)(parts, theme, 8) + '</div>' +
            '<span style="text-align:right;font-weight:800;font-variant-numeric:tabular-nums">' + (0, Visual_1.count)(t) + '</span></div>';
    });
    return (0, Visual_1.card)(head + '<div style="margin-top:8px">' + (0, Visual_1.showAll)(rows, 8, 'roles') + '</div>', theme, (0, ChartKit_1.str)(b.tone) === 'bad' || (0, ChartKit_1.str)(b.tone) === 'ok' ? colour : undefined);
}

};
 defs['ChartKit']=function(module,exports,require){
"use strict";
// Shared drawing helpers for the chart web part: escaping, reading loosely
// typed JSON, colours, text measuring and wrapping, and SVG fragments. Every
// chart builds a string of markup; anything taken from the chart data goes
// through esc() first.
Object.defineProperty(exports, "__esModule", { value: true });
exports.tint = exports.niceTicks = exports.legendHtml = exports.marker = exports.rect = exports.r = exports.svgText = exports.svgDoc = exports.nextId = exports.widest = exports.wrapText = exports.textWidth = exports.setTextMeasurer = exports.readableOn = exports.colourFor = exports.safeHref = exports.setSiteUrl = exports.compact = exports.fmt = exports.esc = exports.list = exports.num = exports.str = exports.isNil = exports.SERIES = exports.FONT = void 0;
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
// A large figure in compact form for a tight space: 2.36M, 236K, 4.1B.
function compact(value) {
    const units = [[1e9, 'B'], [1e6, 'M'], [1e3, 'K']];
    for (const [size, unit] of units) {
        if (Math.abs(value) >= size) {
            const x = value / size;
            const digits = Math.abs(x) >= 100 ? 0 : Math.abs(x) >= 10 ? 1 : 2;
            return parseFloat(x.toFixed(digits)).toString() + unit;
        }
    }
    return fmt(value);
}
exports.compact = compact;
// The site the charts are drawn on, for the publisher's ~site/ links. The
// chart web part sets it to its site's server-relative URL.
let siteBase = '';
function setSiteUrl(url) {
    siteBase = str(url).replace(/\/+$/, '');
}
exports.setSiteUrl = setSiteUrl;
// Only links the publisher writes: web URLs, mail, site-relative paths, and
// ~site/ paths, which resolve against the site.
function safeHref(href) {
    let h = str(href).trim();
    if (h.indexOf('~site/') === 0) {
        h = siteBase + h.substring(5);
    }
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
// A colour, see-through, for fills and borders; a theme colour that is not
// six-digit hex is mixed with transparent instead.
function tint(hex, alpha) {
    const m = /^#?([0-9a-f]{6})$/i.exec(str(hex).trim());
    if (!m) {
        return 'color-mix(in srgb,' + esc(hex) + ' ' + Math.round(alpha * 100) + '%,transparent)';
    }
    const v = parseInt(m[1], 16);
    return 'rgba(' + ((v >> 16) & 255) + ',' + ((v >> 8) & 255) + ',' + (v & 255) + ',' + alpha + ')';
}
exports.tint = tint;

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
 defs['CostBreakdownChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderCostBreakdown = void 0;
const ChartKit_1 = require("./ChartKit");
const Visual_1 = require("./Visual");
// Where the monthly estimate comes from: the total, then the billable GB by
// plan with each plan's cost, then every source family's GB, each opening
// to every one of its tables with its billing rate. One view of the cost,
// in place of the separate mind map, flow diagram and compact flow.
const PLAN = { Analytics: '#dc2626', Basic: '#0d9488', Auxiliary: '#0891b2', DataLake: '#7c3aed' };
const PLAN_NAME = { DataLake: 'Data lake' };
function renderCostBreakdown(data, theme) {
    const sources = (0, ChartKit_1.list)(data && data.sources).filter((s) => (0, ChartKit_1.num)(s.gb) > 0);
    const plans = (0, ChartKit_1.list)(data && data.plans);
    if (!sources.length && !plans.length) {
        return '';
    }
    const currency = (0, ChartKit_1.str)(data.currency);
    const totalGb = (0, ChartKit_1.num)(data.totalGb) || sources.reduce((a, s) => a + (0, ChartKit_1.num)(s.gb), 0);
    const money = (v) => (0, ChartKit_1.isNil)(v) || (0, ChartKit_1.str)(v) === '' ? '' : (currency ? currency + ' ' : '') + (0, ChartKit_1.fmt)((0, ChartKit_1.num)(v));
    const head = '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px">' +
        (0, Visual_1.card)((0, Visual_1.eyebrow)('Estimated monthly cost', theme) + (0, Visual_1.figure)(money(data.monthlyTotal) || 'n/a', theme, 28) +
            (0, Visual_1.sub)('From the last 30 days of billable data: ' + gb(totalGb) + '.', theme), theme, Visual_1.INFO) +
        plansCard(plans, money, theme) + '</div>';
    return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' + head +
        (sources.length ? sourcesCard(sources, totalGb, theme) : '') + '</div>';
}
exports.renderCostBreakdown = renderCostBreakdown;
function plansCard(plans, money, theme) {
    const parts = plans.map((p, i) => ({ label: PLAN_NAME[(0, ChartKit_1.str)(p.name)] || (0, ChartKit_1.str)(p.name), value: (0, ChartKit_1.num)(p.gb), colour: PLAN[(0, ChartKit_1.str)(p.name)] || ChartKit_1.SERIES[i % ChartKit_1.SERIES.length] }));
    const total = parts.reduce((a, p) => a + p.value, 0);
    const rows = parts.map((p, i) => '<div style="display:grid;grid-template-columns:10px minmax(0,1fr) auto auto;gap:10px;align-items:center;font-size:12px;padding:2px 0">' +
        '<span style="width:10px;height:10px;border-radius:3px;background:' + (0, ChartKit_1.esc)(p.colour) + '"></span>' +
        '<span>' + (0, ChartKit_1.esc)(p.label) + ' <span style="color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, Visual_1.pct)(p.value, total) + '</span></span>' +
        '<span style="font-variant-numeric:tabular-nums;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + gb(p.value) + '</span>' +
        '<span style="font-weight:750;font-variant-numeric:tabular-nums;text-align:right;min-width:84px">' + (0, ChartKit_1.esc)(money(plans[i].cost)) + '</span></div>').join('');
    return (0, Visual_1.card)((0, Visual_1.eyebrow)('By plan', theme) + (0, Visual_1.sub)('Billable GB in 30 days, and each plan\'s monthly cost', theme) +
        '<div style="margin:10px 0 9px">' + (0, Visual_1.meter)(parts, theme, 12) + '</div>' + rows, theme);
}
function sourcesCard(sources, totalGb, theme) {
    const max = Math.max(...sources.map((s) => (0, ChartKit_1.num)(s.gb)));
    const rows = sources.map((s, i) => {
        const tables = (0, ChartKit_1.list)(s.tables);
        const colour = ChartKit_1.SERIES[i % ChartKit_1.SERIES.length];
        const summary = '<summary style="display:grid;grid-template-columns:minmax(140px,1.1fr) minmax(120px,2fr) 80px 44px 76px;gap:12px;align-items:center;cursor:pointer;padding:7px 4px;list-style:none">' +
            '<span style="font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="' + (0, ChartKit_1.esc)(s.name) + '">' + (0, ChartKit_1.esc)(s.name) + '</span>' +
            (0, Visual_1.share)((0, ChartKit_1.num)(s.gb), max, colour, theme) +
            '<span style="text-align:right;font-weight:750;font-variant-numeric:tabular-nums">' + gb((0, ChartKit_1.num)(s.gb)) + '</span>' +
            '<span style="text-align:right;color:' + (0, ChartKit_1.esc)(theme.muted) + ';font-variant-numeric:tabular-nums">' + (0, Visual_1.pct)((0, ChartKit_1.num)(s.gb), totalGb) + '</span>' +
            '<span style="justify-self:end">' + (0, Visual_1.chip)(tables.length + ' table' + (tables.length === 1 ? '' : 's'), theme) + '</span></summary>';
        const detail = '<div style="margin:2px 0 8px;padding:6px 10px;border-radius:9px;background:' + (0, ChartKit_1.tint)(colour, theme.dark ? 0.08 : 0.04) + '">' +
            tables.map((t) => '<div style="display:grid;grid-template-columns:minmax(0,1fr) auto 80px;gap:12px;align-items:center;font-size:12px;padding:3px 0">' +
                '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace" title="' + (0, ChartKit_1.esc)(t.table) + '">' + (0, ChartKit_1.esc)(t.table) + '</span>' +
                '<span style="font-size:11px;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, ChartKit_1.esc)(t.tier) + '</span>' +
                '<span style="text-align:right;font-variant-numeric:tabular-nums">' + gb((0, ChartKit_1.num)(t.gb)) + '</span></div>').join('') + '</div>';
        return '<details style="border-top:1px solid ' + (0, ChartKit_1.esc)(theme.line) + '">' + summary + detail + '</details>';
    }).join('');
    return (0, Visual_1.card)((0, Visual_1.eyebrow)('By source', theme) + (0, Visual_1.sub)('Every source family\'s billable GB; select one for its tables and billing rate', theme) +
        '<div style="margin-top:8px">' + rows + '</div>', theme);
}
function gb(v) {
    return (v >= 100 ? Math.round(v).toLocaleString('en-GB') : v >= 10 ? (Math.round(v * 10) / 10).toString() : (Math.round(v * 100) / 100).toString()) + ' GB';
}

};
 defs['EstateChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderEstate = void 0;
const ChartKit_1 = require("./ChartKit");
const Visual_1 = require("./Visual");
// The estate in the last 30 days: every source family's billable GB split
// into what an enabled detection reads and what nothing reads, then the
// pipeline from ingestion to incidents as four stages, each with the share
// that made it through and a rating (80% and over strong, 65% fair).
const READ = '#0d9488';
const STAGE = ['#2563eb', '#0d9488', '#d97706', '#7c3aed'];
function renderEstate(data, theme) {
    const sources = (0, ChartKit_1.list)(data && data.sources);
    const stages = (0, ChartKit_1.list)(data && data.stages);
    if (!sources.length && !stages.length) {
        return '';
    }
    return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' +
        (stages.length ? pipeline(stages, theme) : '') + (sources.length ? families(sources, data, theme) : '') + '</div>';
}
exports.renderEstate = renderEstate;
function pipeline(stages, theme) {
    const cols = [];
    stages.forEach((s, i) => {
        if (i) {
            cols.push('40px');
        }
        cols.push('minmax(150px,1fr)');
    });
    let out = '<div style="display:grid;grid-template-columns:' + cols.join(' ') + ';min-width:' + (stages.length * 160 + 120) + 'px;align-items:stretch">';
    stages.forEach((s, i) => {
        const colour = STAGE[i % STAGE.length];
        if (i) {
            out += (0, Visual_1.arrow)(STAGE[(i - 1) % STAGE.length], colour);
        }
        const value = (0, ChartKit_1.num)(s.value);
        const of = (0, ChartKit_1.num)(s.of);
        const p = of > 0 ? value / of : 0;
        const rating = of <= 0 ? '' : p >= 0.8 ? (0, Visual_1.pill)('Strong', Visual_1.OK) : p >= 0.65 ? (0, Visual_1.pill)('Fair', Visual_1.WARN) : (0, Visual_1.pill)('Weak', Visual_1.BAD);
        out += (0, Visual_1.card)('<div style="display:flex;justify-content:space-between;align-items:center;gap:6px">' + (0, Visual_1.eyebrow)((0, ChartKit_1.str)(s.name), theme, colour) + rating + '</div>' +
            (0, Visual_1.figure)(of > 0 ? (0, Visual_1.pct)(value, of) : 'n/a', theme) +
            (0, Visual_1.sub)((0, Visual_1.count)(value) + ' of ' + (0, Visual_1.count)(of) + ' ' + (0, ChartKit_1.str)(s.label), theme) +
            '<div style="margin:9px 0 8px">' + (0, Visual_1.share)(value, of, colour, theme) + '</div>' +
            ((0, ChartKit_1.str)(s.detail) ? '<div style="font-size:12px;font-weight:700">' + (0, ChartKit_1.esc)(s.detail) + '</div>' : ''), theme, colour);
    });
    return out + '</div>';
}
function families(sources, data, theme) {
    const total = (0, ChartKit_1.num)(data.totalGb) || sources.reduce((a, s) => a + (0, ChartKit_1.num)(s.gb), 0);
    const covered = (0, ChartKit_1.num)(data.coveredGb);
    const max = Math.max(...sources.map((s) => (0, ChartKit_1.num)(s.gb)));
    const rows = sources.map((s) => {
        const gb = (0, ChartKit_1.num)(s.gb);
        const read = Math.min(gb, (0, ChartKit_1.num)(s.coveredGb));
        const parts = [{ label: 'Read by a detection', value: read, colour: READ }, { label: 'Not monitored', value: gb - read, colour: Visual_1.NEUTRAL }];
        return '<div style="display:grid;grid-template-columns:minmax(150px,1.2fr) minmax(120px,2fr) 76px 150px;gap:12px;align-items:center;padding:6px 0;border-top:1px solid ' + (0, ChartKit_1.esc)(theme.line) + '">' +
            '<span style="font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="' + (0, ChartKit_1.esc)(s.name) + '">' + (0, ChartKit_1.esc)(s.name) + '</span>' +
            '<div style="width:' + (max > 0 ? gb / max * 100 : 0).toFixed(1) + '%;min-width:6px">' + (0, Visual_1.meter)(parts, theme, 8) + '</div>' +
            '<span style="text-align:right;font-weight:750;font-variant-numeric:tabular-nums">' + gbText(gb) + '</span>' +
            '<span style="text-align:right;font-size:11.5px;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, Visual_1.pct)(read, gb) + ' read · ' + (0, Visual_1.count)((0, ChartKit_1.num)(s.covered)) + '/' + (0, Visual_1.count)((0, ChartKit_1.num)(s.tables)) + ' tables</span></div>';
    });
    const key = '<div style="display:flex;flex-wrap:wrap;gap:14px;font-size:12px;color:' + (0, ChartKit_1.esc)(theme.muted) + ';margin-top:6px">' +
        '<span style="display:inline-flex;align-items:center;gap:6px"><span style="width:10px;height:10px;border-radius:3px;background:' + READ + '"></span>Read by an enabled detection</span>' +
        '<span style="display:inline-flex;align-items:center;gap:6px"><span style="width:10px;height:10px;border-radius:3px;background:' + Visual_1.NEUTRAL + '"></span>Not monitored (ingested and billed, read by no detection)</span></div>';
    return (0, Visual_1.card)('<div style="display:flex;justify-content:space-between;align-items:flex-end;gap:12px">' +
        '<div>' + (0, Visual_1.eyebrow)('Source families', theme) + (0, Visual_1.sub)(gbText(total) + ' billable in 30 days, ' + (0, Visual_1.pct)(covered, total) + ' of it read by a detection', theme) + '</div></div>' +
        key + '<div style="margin-top:8px">' + (0, Visual_1.showAll)(rows, 8, 'families') + '</div>', theme);
}
function gbText(v) {
    return (v >= 100 ? Math.round(v).toLocaleString('en-GB') : v >= 10 ? (Math.round(v * 10) / 10).toString() : (Math.round(v * 100) / 100).toString()) + ' GB';
}

};
 defs['FindingCardsChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderFindingCards = void 0;
const ChartKit_1 = require("./ChartKit");
const Visual_1 = require("./Visual");
// The most severe findings as cards, as the dashboard's Overview shows
// them: severity, id and title, the category, what was found beside how to
// fix it (four lines each; the finding holds the full text), and links to
// the finding and to Microsoft Learn.
const SEVERITY = { Critical: Visual_1.BAD, Warning: Visual_1.WARN, Info: Visual_1.INFO };
const CLAMP = 'display:-webkit-box;-webkit-line-clamp:4;-webkit-box-orient:vertical;overflow:hidden';
function renderFindingCards(data, theme) {
    const cards = (0, ChartKit_1.list)(data && data.cards);
    if (!cards.length) {
        return '';
    }
    return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' +
        cards.map((c) => one(c, theme)).join('') + '</div>';
}
exports.renderFindingCards = renderFindingCards;
function one(c, theme) {
    const colour = SEVERITY[(0, ChartKit_1.str)(c.severity)] || Visual_1.INFO;
    const head = '<div style="display:flex;align-items:baseline;gap:10px;flex-wrap:wrap">' +
        (0, Visual_1.pill)((0, ChartKit_1.str)(c.severity), colour, true) +
        '<b style="font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12.5px">' + (0, ChartKit_1.esc)(c.id) + '</b>' +
        '<span style="font-weight:700;font-size:14px;line-height:1.35">' + (0, ChartKit_1.esc)(c.title) + '</span></div>';
    const meta = (0, ChartKit_1.str)(c.category) ? '<div style="margin-top:8px">' + (0, Visual_1.chip)((0, ChartKit_1.str)(c.category), theme) + '</div>' : '';
    const block = (label, text) => text
        ? '<div style="min-width:0">' + (0, Visual_1.eyebrow)(label, theme) + '<div style="margin-top:4px;font-size:12.5px;line-height:1.55;color:' + (0, ChartKit_1.esc)(theme.text) + ';' + CLAMP + '">' + (0, ChartKit_1.esc)(text) + '</div></div>'
        : '';
    const findingHref = (0, ChartKit_1.safeHref)(c.href);
    const learnHref = (0, ChartKit_1.safeHref)(c.learn);
    const link = (href, text, external) => '<a href="' + (0, ChartKit_1.esc)(href) + '"' + (external ? ' target="_blank" rel="noopener"' : '') + ' style="font-size:12px;font-weight:700;color:' + (0, ChartKit_1.esc)(theme.accent) + ';text-decoration:none">' + (0, ChartKit_1.esc)(text) + ' →</a>';
    const links = [];
    if (findingHref) {
        links.push(link(findingHref, 'Open the finding', false));
    }
    if (learnHref) {
        links.push(link(learnHref, 'Microsoft Learn', true));
    }
    return (0, Visual_1.card)(head + meta +
        '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px 22px;margin-top:12px">' +
        block('What was found', (0, ChartKit_1.str)(c.evidence)) + block('How to fix it', (0, ChartKit_1.str)(c.remediation)) + '</div>' +
        (links.length ? '<div style="display:flex;gap:18px;flex-wrap:wrap;margin-top:12px">' + links.join('') + '</div>' : ''), theme);
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
 defs['IncidentLifecycleChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.duration = exports.renderIncidentLifecycle = void 0;
const ChartKit_1 = require("./ChartKit");
// The incident lifecycle: the window's incidents at their current status
// (New, Active, Closed) as stage tiles, the two ways a closed incident got
// there (acknowledged first, or closed straight from New, which SAC-INC-05
// checks), and how the open ones split by severity and the closed ones by
// classification and by who closed them. A figure the capture lacks is
// left out rather than shown as zero.
const STAGE = { new: '#d97706', active: '#2563eb', closed: '#0d9488' };
const CLOSER = { automationrule: '#7c3aed', analyst: '#2563eb', defenderxdr: '#0891b2', other: '#64748b' };
function renderIncidentLifecycle(data, theme) {
    if (!data || (0, ChartKit_1.isNil)(data.raised)) {
        return '';
    }
    const raised = (0, ChartKit_1.num)(data.raised);
    const days = (0, ChartKit_1.num)(data.days) || 30;
    if (raised <= 0) {
        return '<p style="margin:0;color:' + (0, ChartKit_1.esc)(theme.muted) + '">No incidents were raised in the last ' + days + ' days.</p>';
    }
    return '<div style="display:flex;flex-direction:column;gap:16px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' +
        pipeline(data, theme, raised, days) +
        '<p style="margin:0;font-size:12px;color:' + (0, ChartKit_1.esc)(theme.muted) + '">Each stage shows where the last ' + days + ' days\' incidents are now; the arrows show how the closed ones got there.</p>' +
        breakdowns(data, theme) +
        '</div>';
}
exports.renderIncidentLifecycle = renderIncidentLifecycle;
function pipeline(data, theme, raised, days) {
    const closed = opt(data.closed);
    const ack = opt(data.acknowledged);
    const unack = opt(data.unacknowledged);
    const mtta = opt(data.mttaMinutes);
    const mttr = opt(data.mttrMinutes);
    const unified = opt(data.unified);
    const cols = 'minmax(118px,1fr) 52px minmax(118px,1fr) 108px minmax(118px,1fr) 92px minmax(118px,1fr)';
    let out = '<div style="display:grid;grid-template-columns:' + cols + ';min-width:700px;padding-bottom:' + ((0, ChartKit_1.isNil)(unack) ? '0' : '16px') + '">' +
        tile('Raised', theme.accent, raised, 'in the last ' + days + ' days', undefined, (0, ChartKit_1.isNil)(unified) ? '' : count(unified) + ' through Defender XDR', theme) +
        arrow(theme.accent, STAGE.new, '', '', theme) +
        tile('New', STAGE.new, opt(data.new), 'waiting, not yet acknowledged', raised, '', theme) +
        arrow(STAGE.new, STAGE.active, 'Acknowledged', (0, ChartKit_1.isNil)(mtta) ? '' : 'MTTA ' + duration(mtta), theme) +
        tile('Active', STAGE.active, opt(data.active), 'being investigated', raised, '', theme) +
        arrow(STAGE.active, STAGE.closed, 'Resolved', (0, ChartKit_1.isNil)(ack) ? '' : count(ack) + ' closed', theme) +
        tile('Closed', STAGE.closed, closed, (0, ChartKit_1.isNil)(closed) ? '' : pct(closed, raised) + ' of raised', raised, (0, ChartKit_1.isNil)(mttr) ? '' : 'MTTR ' + duration(mttr), theme);
    if (!(0, ChartKit_1.isNil)(unack)) {
        out += bypass(unack, closed, !!(data.check && data.check.fired), (0, ChartKit_1.str)(data.check && data.check.id), theme);
    }
    return out + '</div>';
}
function tile(label, colour, value, sub, of, foot, theme) {
    const share = (0, ChartKit_1.isNil)(value) || (0, ChartKit_1.isNil)(of) || !of ? '' :
        '<div style="margin-top:10px;height:4px;border-radius:99px;background:' + (0, ChartKit_1.tint)(colour, 0.2) + '"><div style="height:100%;border-radius:99px;width:' +
            Math.min(100, value / of * 100).toFixed(1) + '%;background:' + (0, ChartKit_1.esc)(colour) + '"></div></div>';
    return '<div style="min-width:0;border:1px solid ' + (0, ChartKit_1.tint)(colour, 0.38) + ';border-radius:14px;padding:12px 14px;background:' + (0, ChartKit_1.tint)(colour, theme.dark ? 0.13 : 0.06) + '">' +
        '<div style="font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:' + (0, ChartKit_1.esc)(colour) + '">' + (0, ChartKit_1.esc)(label) + '</div>' +
        '<div style="font-size:28px;font-weight:800;line-height:1.15;margin-top:6px;font-variant-numeric:tabular-nums">' + ((0, ChartKit_1.isNil)(value) ? '<span style="color:' + (0, ChartKit_1.esc)(theme.muted) + '">n/a</span>' : count(value)) + '</div>' +
        (sub ? '<div style="font-size:12px;color:' + (0, ChartKit_1.esc)(theme.muted) + ';margin-top:2px">' + (0, ChartKit_1.esc)(sub) + '</div>' : '') +
        share +
        (foot ? '<div style="font-size:11.5px;font-weight:650;margin-top:8px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' + (0, ChartKit_1.esc)(foot) + '</div>' : '') +
        '</div>';
}
// A connector between two tiles, shaded from one stage's colour to the
// next, with what happens on it above and a figure below.
function arrow(from, to, above, below, theme) {
    const small = 'font-size:11px;line-height:1.3;color:' + (0, ChartKit_1.esc)(theme.muted) + ';text-align:center;min-height:15px';
    return '<div style="display:flex;flex-direction:column;justify-content:center;gap:5px;padding:0 6px">' +
        '<div style="' + small + ';font-weight:700">' + (0, ChartKit_1.esc)(above) + '</div>' +
        '<div style="position:relative;height:2px;margin-right:6px;background:linear-gradient(90deg,' + (0, ChartKit_1.esc)(from) + ',' + (0, ChartKit_1.esc)(to) + ')">' +
        '<span style="position:absolute;right:-7px;top:-4px;border-left:8px solid ' + (0, ChartKit_1.esc)(to) + ';border-top:5px solid transparent;border-bottom:5px solid transparent"></span></div>' +
        '<div style="' + small + ';font-weight:650;color:' + (0, ChartKit_1.esc)(theme.text) + '">' + (0, ChartKit_1.esc)(below) + '</div>' +
        '</div>';
}
// The path from New straight to Closed, under the tiles: dashed, red with
// the check's id when the check fired, faint when nothing took it.
function bypass(unack, closed, fired, checkId, theme) {
    const colour = unack <= 0 ? theme.line : fired ? '#dc2626' : '#d97706';
    const line = '2px dashed ' + (0, ChartKit_1.esc)(colour);
    const share = (0, ChartKit_1.isNil)(closed) || !closed ? '' : ' (' + pct(unack, closed) + ' of closed)';
    const text = unack <= 0 ? 'None closed without acknowledgement' : count(unack) + ' closed without acknowledgement' + share;
    const badge = fired && checkId
        ? '<span style="margin-left:8px;padding:1px 7px;border-radius:5px;background:#dc2626;color:#fff;font-weight:800;font-size:10.5px">' + (0, ChartKit_1.esc)(checkId) + '</span>' : '';
    return '<div style="grid-column:3;height:26px;margin-left:50%;border-left:' + line + ';border-bottom:' + line + ';border-bottom-left-radius:14px"></div>' +
        '<div style="grid-column:4 / 7;height:26px;border-bottom:' + line + ';position:relative">' +
        '<span style="position:absolute;left:50%;bottom:-13px;transform:translateX(-50%);white-space:nowrap;padding:3px 10px;border-radius:99px;font-size:11.5px;font-weight:700;' +
        'border:1px solid ' + (0, ChartKit_1.esc)(colour) + ';background:' + (0, ChartKit_1.esc)(theme.surface) + ';color:' + (0, ChartKit_1.esc)(unack <= 0 ? theme.muted : theme.text) + '">' + (0, ChartKit_1.esc)(text) + badge + '</span></div>' +
        '<div style="grid-column:7;height:26px;margin-right:50%;border-right:' + line + ';border-bottom:' + line + ';border-bottom-right-radius:14px;position:relative">' +
        '<span style="position:absolute;right:-6px;top:-1px;border-bottom:8px solid ' + (0, ChartKit_1.esc)(colour) + ';border-left:5px solid transparent;border-right:5px solid transparent"></span></div>';
}
function breakdowns(data, theme) {
    const open = (0, ChartKit_1.num)(data.new) + (0, ChartKit_1.num)(data.active);
    const panels = [
        panel('Open now, by severity', (0, ChartKit_1.list)(data.openBySeverity), (l, i) => (0, ChartKit_1.colourFor)(l, i), (0, ChartKit_1.isNil)(data.new) && (0, ChartKit_1.isNil)(data.active) ? 'Not captured in this snapshot.' : open <= 0 ? 'No incidents are open.' : 'Not captured in this snapshot.', theme),
        panel('Closed, by classification', (0, ChartKit_1.list)(data.classification), (l, i) => (0, ChartKit_1.colourFor)(l, i), 'Not captured in this snapshot.', theme),
        panel('Closed by', (0, ChartKit_1.list)(data.closedBy), (l, i) => CLOSER[l.toLowerCase().replace(/[^a-z]/g, '')] || (0, ChartKit_1.colourFor)(l, i), 'Not captured in this snapshot.', theme)
    ];
    return '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px">' + panels.join('') + '</div>';
}
// One breakdown: a stacked bar and a legend row per part with its count and
// share.
function panel(title, parts, colour, empty, theme) {
    const rows = parts.filter((p) => (0, ChartKit_1.num)(p.count) > 0);
    const total = rows.reduce((s, p) => s + (0, ChartKit_1.num)(p.count), 0);
    let body;
    if (!total) {
        body = '<p style="margin:8px 0 0;font-size:12px;font-style:italic;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, ChartKit_1.esc)(empty) + '</p>';
    }
    else {
        body = '<div style="display:flex;height:10px;border-radius:99px;overflow:hidden;margin:10px 0 10px;gap:2px">' +
            rows.map((p, i) => '<span title="' + (0, ChartKit_1.esc)((0, ChartKit_1.str)(p.label) + ': ' + count((0, ChartKit_1.num)(p.count))) + '" style="flex:' + (0, ChartKit_1.num)(p.count) + ' 1 0;min-width:3px;background:' + (0, ChartKit_1.esc)(colour((0, ChartKit_1.str)(p.label), i)) + '"></span>').join('') +
            '</div>' +
            rows.map((p, i) => '<div style="display:grid;grid-template-columns:10px minmax(0,1fr) auto 42px;gap:8px;align-items:center;font-size:12px;padding:2px 0">' +
                '<span style="width:10px;height:10px;border-radius:3px;background:' + (0, ChartKit_1.esc)(colour((0, ChartKit_1.str)(p.label), i)) + '"></span>' +
                '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + (0, ChartKit_1.esc)(p.label) + '</span>' +
                '<span style="font-weight:700;font-variant-numeric:tabular-nums">' + count((0, ChartKit_1.num)(p.count)) + '</span>' +
                '<span style="text-align:right;color:' + (0, ChartKit_1.esc)(theme.muted) + ';font-variant-numeric:tabular-nums">' + pct((0, ChartKit_1.num)(p.count), total) + '</span></div>').join('');
    }
    return '<div style="min-width:0;border:1px solid ' + (0, ChartKit_1.esc)(theme.line) + ';border-radius:12px;padding:11px 14px 12px">' +
        '<div style="font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, ChartKit_1.esc)(title) + '</div>' +
        body + '</div>';
}
function opt(value) {
    return (0, ChartKit_1.isNil)(value) || (0, ChartKit_1.str)(value) === '' ? undefined : (0, ChartKit_1.num)(value);
}
function count(n) {
    return Math.round(n).toLocaleString('en-GB');
}
function pct(part, whole) {
    return whole > 0 ? Math.round(part / whole * 100) + '%' : '0%';
}
// Minutes as the dashboard writes them: 45m, 3h 20m, 1d 11h.
function duration(minutes) {
    const m = Math.round(minutes);
    if (m < 1) {
        return '< 1m';
    }
    if (m < 60) {
        return m + 'm';
    }
    if (m < 1440) {
        return Math.floor(m / 60) + 'h' + (m % 60 ? ' ' + (m % 60) + 'm' : '');
    }
    let d = Math.floor(m / 1440);
    let h = Math.round((m % 1440) / 60);
    if (h === 24) {
        d += 1;
        h = 0;
    }
    return d + 'd' + (h ? ' ' + h + 'h' : '');
}
exports.duration = duration;

};
 defs['JourneyChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderJourney = void 0;
const ChartKit_1 = require("./ChartKit");
// A user journey as a journey map: the stages across the top, one column
// per step, and a curve through the steps' scores (5 at the top, smooth;
// 1 at the bottom, friction), so the pain points read as the dips. Each
// point carries its score; the step and who does it sit underneath.
const STEP_MIN = 88;
const GUTTER = 62;
const PLOT = 150;
const PAD = 18;
function renderJourney(data, theme) {
    const sections = (0, ChartKit_1.list)(data && data.sections)
        .filter((s) => (0, ChartKit_1.list)(s.tasks).length > 0);
    const steps = [];
    sections.forEach((s) => {
        (0, ChartKit_1.list)(s.tasks).forEach((t) => {
            steps.push({ task: t, score: Math.max(1, Math.min(5, Math.round((0, ChartKit_1.num)(t.score)))) });
        });
    });
    if (!steps.length) {
        return '';
    }
    const n = steps.length;
    const cols = 'repeat(' + n + ',minmax(' + STEP_MIN + 'px,1fr))';
    return '<div style="min-width:' + (n * STEP_MIN + GUTTER) + 'px;padding-left:' + GUTTER + 'px;font-size:12.5px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' +
        stages(sections, cols, theme) + plot(steps, sections, theme) + labels(steps, cols, theme) + '</div>';
}
exports.renderJourney = renderJourney;
// Each stage's name over its steps, on a soft chip with a hairline under it
// to the stage's edges.
function stages(sections, cols, theme) {
    return '<div style="display:grid;grid-template-columns:' + cols + '">' +
        sections.map((s) => '<div style="grid-column:span ' + (0, ChartKit_1.list)(s.tasks).length + ';min-width:0;margin:0 4px;text-align:center;padding-bottom:7px;border-bottom:1px solid ' + (0, ChartKit_1.esc)(theme.line) + '">' +
            '<span style="display:inline-block;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;padding:3px 10px;border-radius:99px;font-size:10.5px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;' +
            'color:' + (0, ChartKit_1.esc)(theme.muted) + ';background:' + (0, ChartKit_1.tint)(theme.accent, theme.dark ? 0.16 : 0.08) + '">' + (0, ChartKit_1.esc)(s.name) + '</span></div>').join('') +
        '</div>';
}
// The curve and its points. The line is drawn in a stretched SVG so it
// spans the columns exactly; the points are HTML on top, so they stay round.
function plot(steps, sections, theme) {
    const n = steps.length;
    const w = n * 100;
    const y = (s) => PAD + (5 - s) / 4 * (PLOT - 2 * PAD);
    const pts = steps.map((s, i) => [i * 100 + 50, y(s.score)]);
    let curve = 'M' + pts[0][0] + ' ' + pts[0][1];
    for (let i = 1; i < pts.length; i++) {
        const mid = (pts[i - 1][0] + pts[i][0]) / 2;
        curve += ' C' + mid + ' ' + pts[i - 1][1] + ' ' + mid + ' ' + pts[i][1] + ' ' + pts[i][0] + ' ' + pts[i][1];
    }
    const area = curve + ' L' + pts[pts.length - 1][0] + ' ' + PLOT + ' L' + pts[0][0] + ' ' + PLOT + ' Z';
    const grad = (0, ChartKit_1.nextId)('journey');
    let guides = '';
    for (let s = 1; s <= 5; s++) {
        guides += '<line x1="0" x2="' + w + '" y1="' + y(s) + '" y2="' + y(s) + '" stroke="' + (0, ChartKit_1.esc)(theme.line) + '" stroke-dasharray="3 4" vector-effect="non-scaling-stroke"/>';
    }
    let x = 0;
    sections.slice(0, -1).forEach((sec) => {
        x += (0, ChartKit_1.list)(sec.tasks).length * 100;
        guides += '<line x1="' + x + '" x2="' + x + '" y1="0" y2="' + PLOT + '" stroke="' + (0, ChartKit_1.esc)(theme.line) + '" vector-effect="non-scaling-stroke"/>';
    });
    const bandH = y(4) - y(5) + PAD;
    const svg = '<svg viewBox="0 0 ' + w + ' ' + PLOT + '" preserveAspectRatio="none" aria-hidden="true" style="position:absolute;inset:0;width:100%;height:100%;overflow:visible">' +
        '<defs><linearGradient id="' + grad + '" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' + (0, ChartKit_1.esc)(theme.accent) + '" stop-opacity="' + (theme.dark ? 0.32 : 0.2) + '"/>' +
        '<stop offset="1" stop-color="' + (0, ChartKit_1.esc)(theme.accent) + '" stop-opacity="0"/></linearGradient></defs>' +
        '<rect x="0" y="0" width="' + w + '" height="' + bandH + '" fill="#16a34a" fill-opacity="' + (theme.dark ? 0.07 : 0.05) + '"/>' +
        '<rect x="0" y="' + (PLOT - bandH) + '" width="' + w + '" height="' + bandH + '" fill="#dc2626" fill-opacity="' + (theme.dark ? 0.08 : 0.05) + '"/>' +
        guides +
        '<path d="' + area + '" fill="url(#' + grad + ')"/>' +
        '<path d="' + curve + '" fill="none" stroke="' + (0, ChartKit_1.esc)(theme.accent) + '" stroke-width="2.5" stroke-linecap="round" vector-effect="non-scaling-stroke"/>' +
        '</svg>';
    const zone = (text, top) => '<span style="position:absolute;left:-' + GUTTER + 'px;width:' + (GUTTER - 10) + 'px;text-align:right;' + (top ? 'top:6px' : 'bottom:6px') + ';font-size:9.5px;font-weight:800;letter-spacing:.12em;text-transform:uppercase;color:' + (0, ChartKit_1.esc)(top ? '#16a34a' : '#dc2626') + '">' + text + '</span>';
    const dots = steps.map((s, i) => {
        const colour = scoreColour(s.score);
        return '<span role="img" aria-label="' + (0, ChartKit_1.esc)((0, ChartKit_1.str)(s.task.label) + ': score ' + s.score + ' of 5') + '" title="' + (0, ChartKit_1.esc)((0, ChartKit_1.str)(s.task.label) + ': ' + s.score + ' of 5') + '" style="position:absolute;left:' +
            ((i + 0.5) / n * 100).toFixed(3) + '%;top:' + (y(s.score) / PLOT * 100).toFixed(3) + '%;transform:translate(-50%,-50%);width:24px;height:24px;border-radius:50%;' +
            'display:flex;align-items:center;justify-content:center;font-size:11.5px;font-weight:800;color:#fff;background:' + colour + ';box-shadow:0 0 0 3px ' + (0, ChartKit_1.esc)(theme.surface) + ',0 0 0 4px ' + (0, ChartKit_1.tint)(colour, 0.45) + '">' + s.score + '</span>';
    }).join('');
    return '<div style="position:relative;height:' + PLOT + 'px;margin:14px 0 10px">' + svg + zone('Smooth', true) + zone('Friction', false) + dots + '</div>';
}
function labels(steps, cols, theme) {
    return '<div style="display:grid;grid-template-columns:' + cols + '">' +
        steps.map((s) => {
            const actors = (0, ChartKit_1.list)(s.task.actors).map((a) => (0, ChartKit_1.str)(a)).filter((a) => !!a);
            return '<div style="min-width:0;text-align:center;padding:0 4px">' +
                '<div style="font-weight:700;line-height:1.3;color:' + (0, ChartKit_1.esc)(s.score <= 2 ? scoreColour(s.score) : theme.text) + '">' + (0, ChartKit_1.esc)(s.task.label) + '</div>' +
                (actors.length ? '<div style="margin-top:3px;font-size:11.5px;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + actors.map((a) => (0, ChartKit_1.esc)(a)).join(', ') + '</div>' : '') +
                '</div>';
        }).join('') +
        '</div>';
}
function scoreColour(score) {
    return score >= 4 ? '#16a34a' : score === 3 ? '#d97706' : '#dc2626';
}

};
 defs['LakeChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderLake = void 0;
const ChartKit_1 = require("./ChartKit");
const Visual_1 = require("./Visual");
// The Sentinel data lake's tiers on this workspace: the Analytics tier and
// how much of it is mirrored or kept longer in the lake, the lake-only
// tier, the lake they both land in, and the ways the lake is worked with.
const ANA = '#d97706';
const LAKE = '#2563eb';
const ONLY = '#0891b2';
const USE = '#16a34a';
function renderLake(data, theme) {
    if (!data) {
        return '';
    }
    const analytics = (0, ChartKit_1.num)(data.analyticsOnly) + (0, ChartKit_1.num)(data.mirrored) + (0, ChartKit_1.num)(data.extended);
    const lakeOnly = (0, ChartKit_1.num)(data.lakeOnly);
    const uses = (0, ChartKit_1.list)(data.uses);
    const left = '<div style="display:flex;flex-direction:column;gap:12px">' +
        (0, Visual_1.card)((0, Visual_1.eyebrow)('Analytics tier', theme, ANA) + (0, Visual_1.figure)((0, Visual_1.count)(analytics) + ' tables', theme, 22) +
            (0, Visual_1.sub)('Real-time KQL and analytics rules', theme) +
            '<div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:9px">' +
            (0, Visual_1.chip)((0, Visual_1.count)((0, ChartKit_1.num)(data.mirrored) + (0, ChartKit_1.num)(data.extended)) + ' mirrored to the lake', theme) +
            (0, Visual_1.chip)((0, Visual_1.count)((0, ChartKit_1.num)(data.extended)) + ' kept longer in the lake', theme) +
            (0, Visual_1.chip)((0, Visual_1.count)((0, ChartKit_1.num)(data.analyticsOnly)) + ' Analytics only', theme) + '</div>', theme, ANA) +
        (0, Visual_1.card)((0, Visual_1.eyebrow)('Lake-only tier', theme, ONLY) + (0, Visual_1.figure)((0, Visual_1.count)(lakeOnly) + ' tables', theme, 22) +
            (0, Visual_1.sub)('Verbose, rarely queried data, straight to the lake; no real-time rules', theme), theme, lakeOnly > 0 ? ONLY : undefined, lakeOnly > 0 ? '' : 'opacity:.7') +
        '</div>';
    const lake = (0, Visual_1.card)((0, Visual_1.eyebrow)('Sentinel data lake', theme, LAKE) +
        '<div style="font-size:15px;font-weight:800;margin-top:6px">Up to ' + (0, ChartKit_1.esc)((0, ChartKit_1.str)(data.retentionYears) || '12') + ' years of affordable retention</div>' +
        (0, Visual_1.sub)('Stored as Parquet, about 6:1 compressed. The Analytics tier mirrors to it automatically.', theme), theme, LAKE, 'display:flex;flex-direction:column;justify-content:center');
    const use = uses.length
        ? '<div>' + (0, Visual_1.eyebrow)('Working with the lake', theme) +
            '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin-top:8px">' +
            uses.map((u) => '<div style="min-width:0;border-radius:10px;padding:9px 11px;background:' + (0, ChartKit_1.tint)(USE, theme.dark ? 0.1 : 0.05) + ';border:1px solid ' + (0, ChartKit_1.tint)(USE, 0.3) + '">' +
                '<div style="font-size:12.5px;font-weight:750">' + (0, ChartKit_1.esc)(u.name) + '</div>' +
                '<div style="font-size:11.5px;color:' + (0, ChartKit_1.esc)(theme.muted) + ';margin-top:2px;line-height:1.4">' + (0, ChartKit_1.esc)(u.detail) + '</div></div>').join('') + '</div></div>'
        : '';
    return '<div style="display:flex;flex-direction:column;gap:14px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' +
        '<div style="display:grid;grid-template-columns:minmax(240px,1fr) 44px minmax(220px,.9fr);min-width:540px;align-items:stretch">' +
        left + (0, Visual_1.arrow)(ANA, LAKE) + lake + '</div>' + use + '</div>';
}
exports.renderLake = renderLake;

};
 defs['MetersChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderMeters = void 0;
const ChartKit_1 = require("./ChartKit");
const Visual_1 = require("./Visual");
// Proportions of a whole, one card each: what the whole is and its size,
// then a stacked bar of its parts and a legend row per part with its
// count and share. For figures that are parts of something (templates
// deployed or not, packages up to date or not), where a bar chart of the
// same numbers would only repeat the tiles beside it. Figures that belong
// with them but are not parts of a whole sit in a strip underneath.
const TONE = {
    ok: Visual_1.OK, warn: Visual_1.WARN, bad: Visual_1.BAD, info: Visual_1.INFO, neutral: Visual_1.NEUTRAL,
    violet: '#7c3aed', teal: '#0d9488', cyan: '#0891b2', rose: '#db2777'
};
function renderMeters(data, theme) {
    const meters = (0, ChartKit_1.list)(data && data.meters);
    if (!meters.length) {
        return '';
    }
    const figures = (0, ChartKit_1.list)(data.figures);
    return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' +
        '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:12px">' +
        meters.map((m) => one(m, theme)).join('') + '</div>' +
        (figures.length ? strip(figures, theme) : '') + '</div>';
}
exports.renderMeters = renderMeters;
// The figures side by side across the full width, split by hairlines.
function strip(figures, theme) {
    return (0, Visual_1.card)('<div style="display:grid;grid-template-columns:repeat(' + figures.length + ',minmax(0,1fr))">' +
        figures.map((f, i) => '<div style="min-width:0;padding:2px 16px;' + (i ? 'border-left:1px solid ' + (0, ChartKit_1.esc)(theme.line) : 'padding-left:0') + '">' +
            (0, Visual_1.eyebrow)((0, ChartKit_1.str)(f.label), theme) +
            '<div style="font-size:24px;font-weight:800;line-height:1.15;margin-top:5px;font-variant-numeric:tabular-nums">' + (0, Visual_1.count)((0, ChartKit_1.num)(f.value)) + '</div>' +
            (0, Visual_1.sub)((0, ChartKit_1.str)(f.caption), theme) + '</div>').join('') + '</div>', theme);
}
function one(m, theme) {
    const parts = (0, ChartKit_1.list)(m.parts).map((p, i) => ({
        label: (0, ChartKit_1.str)(p.label), value: Math.max(0, (0, ChartKit_1.num)(p.value)), colour: TONE[(0, ChartKit_1.str)(p.tone)] || ChartKit_1.SERIES[i % ChartKit_1.SERIES.length]
    }));
    const total = !(0, ChartKit_1.isNil)(m.total) ? (0, ChartKit_1.num)(m.total) : parts.reduce((s, p) => s + p.value, 0);
    const head = '<div style="display:flex;justify-content:space-between;align-items:flex-end;gap:12px">' +
        '<div style="min-width:0">' + (0, Visual_1.eyebrow)((0, ChartKit_1.str)(m.title), theme) + (0, Visual_1.sub)((0, ChartKit_1.str)(m.caption), theme) + '</div>' +
        '<div style="flex:none;font-size:26px;font-weight:800;line-height:1;font-variant-numeric:tabular-nums">' + (0, Visual_1.count)(total) + '</div></div>';
    return (0, Visual_1.card)(head +
        '<div style="margin:12px 0 10px">' + (0, Visual_1.meter)(parts, theme, 12) + '</div>' +
        parts.map((p) => (0, Visual_1.legendRow)(p, total, theme)).join(''), theme);
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
    // The total fits inside the hole: a large one in compact form (2.36M),
    // the legend keeping every exact figure, and smaller type if need be.
    const room = INNER * 2 - 18;
    let shown = total > 0 ? (0, ChartKit_1.fmt)(total) : '0';
    if ((0, ChartKit_1.textWidth)(shown, 26, true) > room) {
        shown = (0, ChartKit_1.compact)(total);
    }
    const size = Math.max(14, Math.min(26, Math.floor(26 * room / Math.max(room, (0, ChartKit_1.textWidth)(shown, 26, true)))));
    const centre = (0, ChartKit_1.svgText)(c, c - 8, [shown], { size: size, weight: 600, fill: theme.text, anchor: 'middle' }) +
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
 defs['ResponseChainChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderResponseChain = void 0;
const ChartKit_1 = require("./ChartKit");
const Visual_1 = require("./Visual");
// The alert-to-response chain as the target shape against this workspace:
// the phases in order, each with this workspace's figure, and its numbered
// steps; a step this workspace is missing, or has at risk, carries the
// finding that says so.
const STATE = {
    ok: { colour: Visual_1.OK, label: 'In place' },
    missing: { colour: Visual_1.BAD, label: 'Missing' },
    risk: { colour: Visual_1.WARN, label: 'At risk' }
};
function renderResponseChain(data, theme) {
    const phases = (0, ChartKit_1.list)(data && data.phases).filter((p) => (0, ChartKit_1.list)(p.steps).length > 0);
    if (!phases.length) {
        return '';
    }
    return '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(178px,1fr));gap:12px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' +
        phases.map((p, i) => phase(p, i, theme)).join('') + '</div>';
}
exports.renderResponseChain = renderResponseChain;
function phase(p, index, theme) {
    const steps = (0, ChartKit_1.list)(p.steps);
    const worst = steps.some((s) => s.state === 'missing') ? 'missing'
        : steps.some((s) => s.state === 'risk') ? 'risk' : '';
    const head = '<div style="display:flex;align-items:center;gap:8px">' +
        '<span style="flex:none;font-size:10.5px;font-weight:800;color:' + (0, ChartKit_1.esc)(theme.muted) + ';font-variant-numeric:tabular-nums">' + (index + 1) + '</span>' +
        (0, Visual_1.eyebrow)((0, ChartKit_1.str)(p.name), theme) + '</div>' +
        ((0, ChartKit_1.str)(p.figure) ? '<div style="font-size:13px;font-weight:750;margin:6px 0 2px">' + (0, ChartKit_1.esc)(p.figure) + '</div>' : '');
    const body = steps.map((s) => step(s, theme)).join('');
    return (0, Visual_1.card)(head + '<div style="display:flex;flex-direction:column;gap:9px;margin-top:10px">' + body + '</div>', theme, worst ? STATE[worst].colour : undefined);
}
function step(s, theme) {
    const state = STATE[(0, ChartKit_1.str)(s.state)];
    const dot = state && s.state !== 'ok' ? state.colour : theme.accent;
    const flag = state && s.state !== 'ok'
        ? '<div style="margin-top:4px">' + (0, Visual_1.pill)(state.label + ((0, ChartKit_1.str)(s.finding) ? ' · ' + (0, ChartKit_1.str)(s.finding) : ''), state.colour) + '</div>'
        : '';
    return '<div style="display:grid;grid-template-columns:22px minmax(0,1fr);gap:8px;align-items:start">' +
        '<span style="width:22px;height:22px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:800;' +
        'color:' + (0, ChartKit_1.esc)(dot) + ';background:' + (0, ChartKit_1.tint)(dot, theme.dark ? 0.2 : 0.12) + '">' + (0, ChartKit_1.esc)(s.n) + '</span>' +
        '<div style="min-width:0"><div style="font-weight:650;line-height:1.35">' + (0, ChartKit_1.esc)(s.action) + '</div>' +
        '<div style="font-size:11.5px;color:' + (0, ChartKit_1.esc)(theme.muted) + ';margin-top:1px">' + (0, ChartKit_1.esc)(s.actor) + ((0, ChartKit_1.str)(s.target) ? ' → ' + (0, ChartKit_1.esc)(s.target) : '') + '</div>' +
        flag + '</div></div>';
}

};
 defs['RuleKindsChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderRuleKinds = void 0;
const ChartKit_1 = require("./ChartKit");
const Visual_1 = require("./Visual");
// The analytics rule kinds: what every rule carries, then one card per
// kind with how many this workspace has deployed and enabled, what the
// kind does and the settings only it has. A kind with none deployed is
// shown faded, so the reader sees what is not in use as well.
const COLOUR = {
    Scheduled: Visual_1.INFO, NRT: '#0d9488', Fusion: '#7c3aed', MicrosoftSecurityIncidentCreation: Visual_1.WARN,
    ThreatIntelligence: '#0891b2', MLBehaviorAnalytics: '#db2777'
};
function renderRuleKinds(data, theme) {
    const kinds = (0, ChartKit_1.list)(data && data.kinds);
    if (!kinds.length) {
        return '';
    }
    const total = (0, ChartKit_1.num)(data.total);
    const common = (0, ChartKit_1.list)(data.common).map((f) => (0, ChartKit_1.str)(f));
    const base = common.length
        ? (0, Visual_1.card)('<div style="display:flex;flex-wrap:wrap;align-items:center;gap:6px 10px">' + (0, Visual_1.eyebrow)('Every rule carries', theme) +
            common.map((f) => (0, Visual_1.chip)(f, theme, true)).join('') + '</div>', theme)
        : '';
    return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' + base +
        '<div style="display:grid;grid-template-columns:repeat(' + (0, Visual_1.balancedColumns)(kinds.length, 5) + ',minmax(170px,1fr));gap:12px">' +
        kinds.map((k) => kindCard(k, total, theme)).join('') + '</div></div>';
}
exports.renderRuleKinds = renderRuleKinds;
function kindCard(k, total, theme) {
    const colour = COLOUR[(0, ChartKit_1.str)(k.kind)] || Visual_1.INFO;
    const deployed = (0, ChartKit_1.num)(k.deployed);
    const enabled = (0, ChartKit_1.num)(k.enabled);
    const fields = (0, ChartKit_1.list)(k.fields).map((f) => (0, ChartKit_1.str)(f));
    const head = '<div style="display:flex;justify-content:space-between;align-items:center;gap:8px">' +
        (0, Visual_1.eyebrow)((0, ChartKit_1.str)(k.label) || (0, ChartKit_1.str)(k.kind), theme, colour) + (k.legacy ? (0, Visual_1.pill)('Legacy', Visual_1.WARN) : '') + '</div>';
    const inner = head +
        (0, Visual_1.figure)((0, Visual_1.count)(deployed), theme) +
        (0, Visual_1.sub)(deployed > 0 ? (0, Visual_1.count)(enabled) + ' enabled' : 'None deployed', theme) +
        '<div style="margin:9px 0 10px">' + (0, Visual_1.share)(deployed, total, colour, theme) + '</div>' +
        '<div style="font-size:12px;line-height:1.5;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, ChartKit_1.esc)(k.summary) + '</div>' +
        (fields.length ? '<div style="display:flex;flex-wrap:wrap;gap:5px;margin-top:9px">' + fields.map((f) => (0, Visual_1.chip)(f, theme, true)).join('') + '</div>' : '');
    return (0, Visual_1.card)(inner, theme, deployed > 0 ? colour : undefined, deployed > 0 ? '' : 'opacity:.62');
}

};
 defs['RunwayChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderRunway = void 0;
const ChartKit_1 = require("./ChartKit");
const Visual_1 = require("./Visual");
// Platform retirements on a time axis: each deadline a numbered marker
// placed by its date, today marked, the past muted; then a card per
// deadline with its date, how long ago or how far off it is, and whether
// this workspace still uses what it retires.
const DAY = 86400000;
function renderRunway(data, theme) {
    const today = Date.parse((0, ChartKit_1.str)(data && data.today)) || Date.now();
    const items = (0, ChartKit_1.list)(data && data.items)
        .map((i) => ({ item: i, at: Date.parse((0, ChartKit_1.str)(i.date)) }))
        .filter((p) => !isNaN(p.at))
        .sort((a, b) => a.at - b.at);
    if (!items.length) {
        return '';
    }
    const first = Math.min(items[0].at, today);
    const last = Math.max(items[items.length - 1].at, today);
    const pad = Math.max(60 * DAY, (last - first) * 0.06);
    const lo = first - pad;
    const hi = last + pad;
    const x = (t) => (t - lo) / (hi - lo) * 100;
    return '<div style="display:flex;flex-direction:column;gap:14px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' +
        axis(items, today, lo, hi, x, theme) +
        '<div style="display:grid;grid-template-columns:repeat(' + (0, Visual_1.balancedColumns)(items.length, 5) + ',minmax(170px,1fr));gap:10px">' +
        items.map((p, i) => itemCard(p, i, today, theme)).join('') + '</div></div>';
}
exports.renderRunway = renderRunway;
function colourOf(p, today) {
    if (p.at < today) {
        return Visual_1.NEUTRAL;
    }
    return (0, ChartKit_1.str)(p.item.state) === 'crit' ? Visual_1.BAD : Visual_1.WARN;
}
function axis(items, today, lo, hi, x, theme) {
    let ticks = '';
    for (let y = new Date(lo).getUTCFullYear() + 1; Date.UTC(y, 0, 1) < hi; y++) {
        ticks += '<span style="position:absolute;left:' + x(Date.UTC(y, 0, 1)).toFixed(2) + '%;top:44px;transform:translateX(-50%);font-size:10.5px;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + y + '</span>' +
            '<span style="position:absolute;left:' + x(Date.UTC(y, 0, 1)).toFixed(2) + '%;top:30px;width:1px;height:8px;background:' + (0, ChartKit_1.esc)(theme.line) + '"></span>';
    }
    const tx = x(today).toFixed(2);
    const markers = items.map((p, i) => {
        const c = colourOf(p, today);
        return '<span title="' + (0, ChartKit_1.esc)((0, ChartKit_1.str)(p.item.label) + ', ' + (0, ChartKit_1.str)(p.item.date)) + '" style="position:absolute;left:' + x(p.at).toFixed(2) + '%;top:22px;transform:translate(-50%,-50%);width:22px;height:22px;border-radius:50%;' +
            'display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:800;color:#fff;background:' + c + ';box-shadow:0 0 0 3px ' + (0, ChartKit_1.esc)(theme.surface) + '">' + (i + 1) + '</span>';
    }).join('');
    return (0, Visual_1.card)('<div style="position:relative;height:62px;margin:0 10px">' +
        '<div style="position:absolute;left:0;right:0;top:21px;height:3px;border-radius:99px;background:linear-gradient(90deg,' + (0, ChartKit_1.tint)(Visual_1.NEUTRAL, 0.35) + ' ' + tx + '%,' + (0, ChartKit_1.tint)(theme.accent, 0.55) + ' ' + tx + '%)"></div>' +
        ticks +
        '<span style="position:absolute;left:' + tx + '%;top:0;bottom:16px;width:2px;background:' + (0, ChartKit_1.esc)(theme.accent) + '"></span>' +
        '<span style="position:absolute;left:' + tx + '%;top:-2px;transform:translateX(6px);font-size:10.5px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:' + (0, ChartKit_1.esc)(theme.accent) + '">Today</span>' +
        markers + '</div>', theme);
}
function itemCard(p, index, today, theme) {
    const c = colourOf(p, today);
    const days = Math.round((p.at - today) / DAY);
    const when = days < 0 ? when2(-days) + ' ago' : days === 0 ? 'Today' : 'In ' + when2(days);
    const status = days < 0 ? (0, Visual_1.pill)('Retired', Visual_1.NEUTRAL) : (0, Visual_1.pill)((0, ChartKit_1.str)(p.item.state) === 'crit' ? 'Retiring' : 'Deprecating', c);
    const use = p.item.inUse;
    const usage = (0, ChartKit_1.isNil)(use) ? (0, Visual_1.pill)('Not readable from the workspace', Visual_1.NEUTRAL)
        : use ? (0, Visual_1.pill)('In use' + ((0, ChartKit_1.str)(p.item.evidence) ? ': ' + (0, ChartKit_1.str)(p.item.evidence) : ''), Visual_1.BAD) : (0, Visual_1.pill)('Not in use', Visual_1.OK);
    const date = new Date(p.at).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
    return (0, Visual_1.card)('<div style="display:flex;align-items:center;gap:8px">' +
        '<span style="flex:none;width:20px;height:20px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:10.5px;font-weight:800;color:#fff;background:' + c + '">' + (index + 1) + '</span>' +
        '<span style="font-size:12px;font-weight:800;font-variant-numeric:tabular-nums">' + (0, ChartKit_1.esc)(date) + '</span>' +
        '<span style="font-size:11.5px;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, ChartKit_1.esc)(when) + '</span></div>' +
        '<div style="font-weight:700;line-height:1.35;margin:7px 0 8px">' + (0, ChartKit_1.esc)(p.item.label) + '</div>' +
        '<div style="display:flex;flex-wrap:wrap;gap:5px">' + status + usage + '</div>', theme, days >= 0 ? c : undefined, days < 0 ? 'opacity:.85' : '');
}
function when2(days) {
    if (days < 45) {
        return days + ' day' + (days === 1 ? '' : 's');
    }
    const months = Math.round(days / 30.4);
    if (months < 18) {
        return months + ' month' + (months === 1 ? '' : 's');
    }
    return (Math.round(days / 365.25 * 10) / 10) + ' years';
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
 defs['TopologyChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderTopology = void 0;
const ChartKit_1 = require("./ChartKit");
const Visual_1 = require("./Visual");
// How data reaches the workspace and where it goes: every source family
// with how many sources feed it, the workspace with the table plans in use
// (and those not in use, faded), and the destinations downstream.
const SRC = '#2563eb';
const WSP = '#d97706';
const DST = '#0d9488';
function renderTopology(data, theme) {
    const sources = (0, ChartKit_1.list)(data && data.sources);
    if (!sources.length) {
        return '';
    }
    const cols = 'minmax(220px,1.15fr) 40px minmax(210px,1fr) 40px minmax(190px,.95fr)';
    // Each card keeps its own height, so opening the source list does not
    // stretch the others; the arrows sit level with the cards' headings.
    const link = (from, to) => '<div style="margin-top:70px">' + (0, Visual_1.arrow)(from, to) + '</div>';
    return '<div style="display:grid;grid-template-columns:' + cols + ';min-width:760px;align-items:start;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' +
        sourcesCard(sources, (0, ChartKit_1.num)(data.sourceTotal), theme) + link(SRC, WSP) + workspaceCard(data, theme) + link(WSP, DST) + downstreamCard((0, ChartKit_1.list)(data.downstream), theme) +
        '</div>';
}
exports.renderTopology = renderTopology;
function sourcesCard(sources, total, theme) {
    const max = Math.max(1, ...sources.map((s) => (0, ChartKit_1.num)(s.count)));
    const rows = sources.map((s) => '<div style="padding:4px 0"><div style="display:flex;justify-content:space-between;gap:8px;font-size:12.5px">' +
        '<span style="min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="' + (0, ChartKit_1.esc)(s.name) + '">' + (0, ChartKit_1.esc)(s.name) + '</span>' +
        '<span style="flex:none;font-weight:750;font-variant-numeric:tabular-nums">' + (0, Visual_1.count)((0, ChartKit_1.num)(s.count)) + '</span></div>' +
        '<div style="margin-top:3px">' + (0, Visual_1.share)((0, ChartKit_1.num)(s.count), max, SRC, theme) + '</div></div>');
    return (0, Visual_1.card)((0, Visual_1.eyebrow)('Connected sources', theme, SRC) + (0, Visual_1.figure)((0, Visual_1.count)(total || sources.reduce((a, s) => a + (0, ChartKit_1.num)(s.count), 0)), theme) +
        (0, Visual_1.sub)(sources.length + ' families, by sources feeding each', theme) +
        '<div style="margin-top:10px">' + (0, Visual_1.showAll)(rows, 10, 'families') + '</div>', theme);
}
function workspaceCard(data, theme) {
    const plans = (0, ChartKit_1.list)(data.plans);
    const rules = (0, ChartKit_1.num)(data.rules);
    const plan = (p) => {
        const on = !!p.inUse;
        return '<div style="border-radius:9px;padding:7px 9px;border:1px solid ' + (on ? (0, ChartKit_1.tint)(Visual_1.OK, 0.35) : (0, ChartKit_1.esc)(theme.line)) + ';background:' + (on ? (0, ChartKit_1.tint)(Visual_1.OK, theme.dark ? 0.12 : 0.06) : 'transparent') + (on ? '' : ';opacity:.6') + '">' +
            '<div style="font-size:12px;font-weight:700">' + (0, ChartKit_1.esc)(p.name) + '</div>' +
            '<div style="font-size:11px;color:' + (0, ChartKit_1.esc)(on ? theme.text : theme.muted) + ';margin-top:1px">' + (0, ChartKit_1.esc)(on ? ((0, ChartKit_1.str)(p.detail) || 'In use') : 'Not in use') + '</div></div>';
    };
    return (0, Visual_1.card)((0, Visual_1.eyebrow)('Sentinel workspace', theme, WSP) +
        '<div style="font-size:15px;font-weight:800;margin-top:5px">Log Analytics workspace</div>' +
        '<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin:10px 0 12px;font-size:12.5px">' +
        '<span style="padding:3px 9px;border-radius:8px;background:' + (0, ChartKit_1.tint)(WSP, 0.16) + ';font-weight:700">' + (0, Visual_1.count)(rules) + ' enabled analytics rules</span>' +
        '<span style="color:' + (0, ChartKit_1.esc)(theme.muted) + '">→</span><span style="padding:3px 9px;border-radius:8px;background:' + (0, ChartKit_1.tint)(WSP, 0.16) + ';font-weight:700">Incidents</span></div>' +
        (0, Visual_1.eyebrow)('Table plans', theme) +
        '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:6px;margin-top:6px">' + plans.map(plan).join('') + '</div>', theme, WSP);
}
function downstreamCard(items, theme) {
    const rows = items.map((d) => {
        const on = !!d.inUse;
        return '<div style="display:flex;justify-content:space-between;align-items:baseline;gap:8px;padding:7px 0;border-top:1px solid ' + (0, ChartKit_1.esc)(theme.line) + (on ? '' : ';opacity:.6') + '">' +
            '<span style="font-size:12.5px;font-weight:650">' + (0, ChartKit_1.esc)(d.name) + '</span>' +
            '<span style="flex:none;font-size:12.5px;font-weight:800;font-variant-numeric:tabular-nums;color:' + (0, ChartKit_1.esc)(on ? theme.text : Visual_1.NEUTRAL) + '">' + (0, ChartKit_1.esc)(on ? ((0, ChartKit_1.str)(d.detail) || 'Yes') : 'None') + '</span></div>';
    }).join('');
    return (0, Visual_1.card)((0, Visual_1.eyebrow)('Downstream', theme, DST) + '<div style="margin-top:8px">' + rows + '</div>', theme);
}

};
 defs['Visual']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.note = exports.balancedColumns = exports.chartStyles = exports.showAll = exports.arrow = exports.legendRow = exports.share = exports.meter = exports.chip = exports.pill = exports.sub = exports.figure = exports.eyebrow = exports.card = exports.pct = exports.count = exports.NEUTRAL = exports.INFO = exports.BAD = exports.WARN = exports.OK = void 0;
const ChartKit_1 = require("./ChartKit");
// The building blocks of the purpose-built graphics, so every one reads in
// the site's style: soft cards on a hairline border, small spaced capitals
// over large tabular figures, tinted fills and pills for meaning, never a
// coloured edge bar. Each returns markup with inline styles, which both
// the SharePoint web part and the dashboard can show as they are.
exports.OK = '#16a34a';
exports.WARN = '#d97706';
exports.BAD = '#dc2626';
exports.INFO = '#2563eb';
exports.NEUTRAL = '#64748b';
function count(n) {
    return Math.round(n).toLocaleString('en-GB');
}
exports.count = count;
function pct(part, whole) {
    return whole > 0 ? Math.round(part / whole * 100) + '%' : '0%';
}
exports.pct = pct;
function card(inner, theme, colour, extra) {
    const fill = colour ? (0, ChartKit_1.tint)(colour, theme.dark ? 0.12 : 0.05) : 'transparent';
    const edge = colour ? (0, ChartKit_1.tint)(colour, 0.35) : (0, ChartKit_1.esc)(theme.line);
    return '<div style="min-width:0;border:1px solid ' + edge + ';border-radius:12px;padding:12px 14px;background:' + fill + (extra ? ';' + extra : '') + '">' + inner + '</div>';
}
exports.card = card;
function eyebrow(text, theme, colour) {
    return '<div style="font-size:10.5px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;color:' + (0, ChartKit_1.esc)(colour || theme.muted) + '">' + (0, ChartKit_1.esc)(text) + '</div>';
}
exports.eyebrow = eyebrow;
function figure(value, theme, size) {
    return '<div style="font-size:' + (size || 26) + 'px;font-weight:800;line-height:1.15;margin-top:4px;font-variant-numeric:tabular-nums;color:' + (0, ChartKit_1.esc)(theme.text) + '">' + (0, ChartKit_1.esc)(value) + '</div>';
}
exports.figure = figure;
function sub(text, theme) {
    return text ? '<div style="font-size:12px;line-height:1.45;color:' + (0, ChartKit_1.esc)(theme.muted) + ';margin-top:3px">' + (0, ChartKit_1.esc)(text) + '</div>' : '';
}
exports.sub = sub;
function pill(text, colour, solid) {
    return '<span style="display:inline-block;white-space:nowrap;padding:1px 8px;border-radius:99px;font-size:10.5px;font-weight:800;' +
        (solid ? 'background:' + (0, ChartKit_1.esc)(colour) + ';color:#fff' : 'background:' + (0, ChartKit_1.tint)(colour, 0.16) + ';color:' + (0, ChartKit_1.esc)(colour)) + '">' + (0, ChartKit_1.esc)(text) + '</span>';
}
exports.pill = pill;
function chip(text, theme, mono) {
    return '<span style="display:inline-block;padding:1px 7px;border-radius:6px;font-size:11px;border:1px solid ' + (0, ChartKit_1.esc)(theme.line) + ';color:' + (0, ChartKit_1.esc)(theme.text) +
        (mono ? ';font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace' : '') + '">' + (0, ChartKit_1.esc)(text) + '</span>';
}
exports.chip = chip;
// A stacked bar of parts, each sized by its value, with a hairline gap.
function meter(parts, theme, height) {
    const shown = parts.filter((p) => (0, ChartKit_1.num)(p.value) > 0);
    if (!shown.length) {
        return '<div style="height:' + (height || 10) + 'px;border-radius:99px;background:' + (0, ChartKit_1.esc)(theme.line) + '"></div>';
    }
    return '<div style="display:flex;gap:2px;height:' + (height || 10) + 'px;border-radius:99px;overflow:hidden">' +
        shown.map((p) => '<span title="' + (0, ChartKit_1.esc)(p.label + ': ' + count(p.value)) + '" style="flex:' + (0, ChartKit_1.num)(p.value) + ' 1 0;min-width:3px;background:' + (0, ChartKit_1.esc)(p.colour) + '"></span>').join('') +
        '</div>';
}
exports.meter = meter;
// One share of a whole: a single bar filled to its fraction.
function share(value, of, colour, theme) {
    const w = of > 0 ? Math.max(0, Math.min(100, value / of * 100)) : 0;
    return '<div style="height:6px;border-radius:99px;background:' + (0, ChartKit_1.tint)(colour, theme.dark ? 0.2 : 0.14) + '"><div style="height:100%;border-radius:99px;width:' + w.toFixed(1) + '%;background:' + (0, ChartKit_1.esc)(colour) + '"></div></div>';
}
exports.share = share;
// A legend row: swatch, label, count and its share of the total.
function legendRow(p, total, theme) {
    return '<div style="display:grid;grid-template-columns:10px minmax(0,1fr) auto 42px;gap:8px;align-items:center;font-size:12px;padding:2px 0">' +
        '<span style="width:10px;height:10px;border-radius:3px;background:' + (0, ChartKit_1.esc)(p.colour) + '"></span>' +
        '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + (0, ChartKit_1.esc)(p.label) + '</span>' +
        '<span style="font-weight:700;font-variant-numeric:tabular-nums">' + count(p.value) + '</span>' +
        '<span style="text-align:right;color:' + (0, ChartKit_1.esc)(theme.muted) + ';font-variant-numeric:tabular-nums">' + pct(p.value, total) + '</span></div>';
}
exports.legendRow = legendRow;
// A right-pointing connector between two columns, shaded between colours.
function arrow(from, to) {
    return '<div style="display:flex;align-items:center;padding:0 4px"><div style="position:relative;flex:1;height:2px;margin-right:7px;background:linear-gradient(90deg,' + (0, ChartKit_1.esc)(from) + ',' + (0, ChartKit_1.esc)(to) + ')">' +
        '<span style="position:absolute;right:-7px;top:-4px;border-left:8px solid ' + (0, ChartKit_1.esc)(to) + ';border-top:5px solid transparent;border-bottom:5px solid transparent"></span></div></div>';
}
exports.arrow = arrow;
// The first rows of a list, then the rest hidden behind the site's one
// button (.sbtn), placed after the whole list so it stays at the foot when
// the list opens: the dashboard's own show-more pattern (.morewrap, rows
// marked data-mr, a data-more button that reads Show fewer when open). The
// dashboard's stylesheet and click handler serve it there; the chart web
// part adds the same (chartStyles, and its own handler) on a SharePoint page.
function showAll(rows, first, noun) {
    if (rows.length <= first) {
        return rows.join('');
    }
    const label = 'Show all ' + rows.length + ' ' + noun;
    return '<div class="morewrap">' +
        rows.map((r, i) => i < first ? r : r.replace(/^<div\b/, '<div data-mr hidden')).join('') +
        '<button type="button" class="sbtn morebtn" data-more data-all="' + (0, ChartKit_1.esc)(label) + '" data-less="Show fewer">' + (0, ChartKit_1.esc)(label) + '</button></div>';
}
exports.showAll = showAll;
// The rules a SharePoint page needs for what the dashboard styles itself:
// the button, its place under a list, and hidden rows staying hidden over
// their inline display. Scoped to the chart web part's own element.
function chartStyles(scope, theme) {
    const s = '.' + scope.replace(/[^\w-]/g, '');
    const accent = theme.accent.replace(/[^#\w(),.%\s-]/g, '');
    const bg = 'linear-gradient(135deg,' + accent + ',' + (theme.dark ? '#5b45c9' : '#6d5efc') + ')';
    return s + ' [hidden]{display:none !important}' +
        s + ' .sbtn{display:inline-flex;align-items:center;justify-content:center;gap:7px;padding:7px 14px;border-radius:10px;font:inherit;font-size:12.5px;font-weight:650;line-height:1.2;' +
        'white-space:nowrap;cursor:pointer;text-decoration:none;background:' + bg + ';color:#fff;border:1px solid transparent;box-shadow:' + (theme.dark ? 'none' : '0 2px 8px rgba(37,99,235,.28)') + ';transition:filter .15s}' +
        s + ' .sbtn:hover{filter:brightness(1.12)}' +
        s + ' .sbtn:focus-visible{outline:2px solid ' + accent + ';outline-offset:2px}' +
        s + ' .morebtn{margin-top:10px}';
}
exports.chartStyles = chartStyles;
// Columns for n cards so the rows balance: six make three and three, never
// five and one. At most max columns.
function balancedColumns(n, max) {
    if (n <= max) {
        return Math.max(1, n);
    }
    return Math.ceil(n / Math.ceil(n / max));
}
exports.balancedColumns = balancedColumns;
function note(text, theme) {
    return '<p style="margin:0;font-size:12px;color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, ChartKit_1.esc)(text) + '</p>';
}
exports.note = note;

};
 defs['WorkspaceAgeChart']=function(module,exports,require){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderWorkspaceAge = void 0;
const ChartKit_1 = require("./ChartKit");
const Visual_1 = require("./Visual");
// The workspace's own history: when it was created and on what terms, how
// old it is, and what it holds today. Platform retirements are on the
// deprecated features page, so they are not repeated here.
function renderWorkspaceAge(data, theme) {
    if (!data) {
        return '';
    }
    const created = Date.parse((0, ChartKit_1.str)(data.created));
    const today = Date.parse((0, ChartKit_1.str)(data.today)) || Date.now();
    const fmtDate = (t) => new Date(t).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
    const age = (0, ChartKit_1.num)(data.ageDays);
    const ageText = (0, ChartKit_1.isNil)(data.ageDays) ? 'Age unknown' : age >= 730 ? (Math.round(age / 365.25 * 10) / 10) + ' years old' : age >= 60 ? Math.round(age / 30.4) + ' months old' : (0, Visual_1.count)(age) + ' days old';
    const terms = [(0, ChartKit_1.str)(data.sku), (0, ChartKit_1.isNil)(data.retentionDays) ? '' : (0, Visual_1.count)((0, ChartKit_1.num)(data.retentionDays)) + '-day retention'].filter((t) => !!t)
        .map((t) => (0, Visual_1.chip)(t, theme)).join(' ');
    const span = '<div style="margin:14px 0 4px">' +
        '<div style="display:flex;justify-content:space-between;gap:12px;font-size:12px;margin-bottom:6px">' +
        '<span><b>Created</b> <span style="color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, ChartKit_1.esc)(isNaN(created) ? 'unknown' : fmtDate(created)) + '</span></span>' +
        '<span><b>Documented</b> <span style="color:' + (0, ChartKit_1.esc)(theme.muted) + '">' + (0, ChartKit_1.esc)(fmtDate(today)) + '</span></span></div>' +
        '<div style="position:relative;height:12px;border-radius:99px;background:linear-gradient(90deg,' + (0, ChartKit_1.tint)(theme.accent, 0.35) + ',' + (0, ChartKit_1.esc)(theme.accent) + ')">' +
        '<span style="position:absolute;left:-3px;top:-3px;width:18px;height:18px;border-radius:50%;background:' + (0, ChartKit_1.esc)(theme.accent) + ';box-shadow:0 0 0 3px ' + (0, ChartKit_1.esc)(theme.surface) + '"></span>' +
        '<span style="position:absolute;right:-3px;top:-3px;width:18px;height:18px;border-radius:50%;background:' + (0, ChartKit_1.esc)(theme.accent) + ';box-shadow:0 0 0 3px ' + (0, ChartKit_1.esc)(theme.surface) + '"></span></div></div>';
    const tile = (label, value, note) => (0, ChartKit_1.isNil)(value) ? '' : (0, Visual_1.card)((0, Visual_1.eyebrow)(label, theme) + (0, Visual_1.figure)((0, Visual_1.count)((0, ChartKit_1.num)(value)), theme, 22) + (0, Visual_1.sub)(note || '', theme), theme);
    const tiles = [
        tile('Analytics rules enabled', data.rulesEnabled),
        tile('Data connectors', data.connectors),
        tile('Tables receiving data', data.tablesReceiving, (0, ChartKit_1.isNil)(data.tablesCatalogue) ? '' : 'of ' + (0, Visual_1.count)((0, ChartKit_1.num)(data.tablesCatalogue)) + ' in the catalogue')
    ].join('');
    return '<div style="display:flex;flex-direction:column;gap:12px;font-size:13px;color:' + (0, ChartKit_1.esc)(theme.text) + '">' +
        (0, Visual_1.card)('<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap">' +
            '<div>' + (0, Visual_1.eyebrow)('Workspace lifespan', theme) + (0, Visual_1.figure)(ageText, theme) + '</div>' +
            '<div style="display:flex;flex-wrap:wrap;gap:6px">' + terms + '</div></div>' + span, theme) +
        (tiles ? '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px">' + tiles + '</div>' : '') +
        '</div>';
}
exports.renderWorkspaceAge = renderWorkspaceAge;

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
const IncidentLifecycleChart_1 = require("./IncidentLifecycleChart");
const MetersChart_1 = require("./MetersChart");
const RuleKindsChart_1 = require("./RuleKindsChart");
const ResponseChainChart_1 = require("./ResponseChainChart");
const TopologyChart_1 = require("./TopologyChart");
const CostBreakdownChart_1 = require("./CostBreakdownChart");
const AccessChart_1 = require("./AccessChart");
const LakeChart_1 = require("./LakeChart");
const EstateChart_1 = require("./EstateChart");
const RunwayChart_1 = require("./RunwayChart");
const WorkspaceAgeChart_1 = require("./WorkspaceAgeChart");
const FindingCardsChart_1 = require("./FindingCardsChart");
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
        case 'incident-lifecycle': return (0, IncidentLifecycleChart_1.renderIncidentLifecycle)(data, theme);
        case 'meters': return (0, MetersChart_1.renderMeters)(data, theme);
        case 'rule-kinds': return (0, RuleKindsChart_1.renderRuleKinds)(data, theme);
        case 'response-chain': return (0, ResponseChainChart_1.renderResponseChain)(data, theme);
        case 'topology': return (0, TopologyChart_1.renderTopology)(data, theme);
        case 'cost-breakdown': return (0, CostBreakdownChart_1.renderCostBreakdown)(data, theme);
        case 'access': return (0, AccessChart_1.renderAccess)(data, theme);
        case 'lake': return (0, LakeChart_1.renderLake)(data, theme);
        case 'estate': return (0, EstateChart_1.renderEstate)(data, theme);
        case 'runway': return (0, RunwayChart_1.renderRunway)(data, theme);
        case 'workspace-age': return (0, WorkspaceAgeChart_1.renderWorkspaceAge)(data, theme);
        case 'finding-cards': return (0, FindingCardsChart_1.renderFindingCards)(data, theme);
        default: return '';
    }
}
function describe(kind) {
    const names = {
        pie: 'Pie chart', xy: 'Bar chart', sankey: 'Flow diagram', timeline: 'Timeline', gantt: 'Schedule',
        mindmap: 'Mind map', flowchart: 'Diagram', state: 'State diagram', class: 'Class diagram',
        sequence: 'Sequence diagram', journey: 'Journey', 'incident-lifecycle': 'Incident lifecycle',
        meters: 'Proportions', 'rule-kinds': 'Rule kinds', 'response-chain': 'Response chain', topology: 'Topology',
        'cost-breakdown': 'Cost breakdown', access: 'Role assignments', lake: 'Data lake tiers',
        estate: 'Estate flow', runway: 'Retirement runway', 'workspace-age': 'Workspace history', 'finding-cards': 'Findings'
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
