/* Life Score charts for the journal.
   Data comes from window.LIFE_SCORE (life-score.js). Each chart draws itself slowly when it
   scrolls into view; with reduced motion it simply appears in its final state. */
(function () {
  'use strict';
  var D = window.LIFE_SCORE;
  if (!D) { return; }
  var NS = 'http://www.w3.org/2000/svg';
  var COL = { happiness: '#9A6A12', achievement: '#2D66B3', growth: '#B2472F', direction: '#0A8C7C', strength: '#4A3F37' };
  var RAMP = ['#DDA48F', '#C97D64', '#B35A40', '#8F3F2B', '#652A1C'];
  var reduce = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);

  function el(tag, attrs, parent) {
    var e = document.createElementNS(NS, tag);
    for (var k in attrs) { if (attrs[k] !== undefined && attrs[k] !== null) { e.setAttribute(k, attrs[k]); } }
    if (parent) { parent.appendChild(e); }
    return e;
  }
  function label(parent, x, y, s, cls, anchor) {
    var t = el('text', { x: x, y: y, 'class': cls || 'ax', 'text-anchor': anchor || 'middle' }, parent);
    t.textContent = s;
    return t;
  }
  function svgIn(mount, w, h, aria) {
    return el('svg', { viewBox: '0 0 ' + w + ' ' + h, role: 'img', 'aria-label': aria, focusable: 'false' }, mount);
  }
  function bin(v) { return v <= 1 ? 0 : v <= 3 ? 1 : v <= 5 ? 2 : v <= 7 ? 3 : 4; }
  function delay(node, ms) { node.style.transitionDelay = ms + 'ms'; return node; }
  /* draw at the real width so text stays readable on phones */
  function widthOf(mount) { return Math.round(Math.max(300, Math.min(640, mount.getBoundingClientRect().width || 640))); }

  /* one shared tooltip */
  var tip = document.createElement('div');
  tip.className = 'chart-tip';
  tip.hidden = true;
  document.body.appendChild(tip);
  function showTip(ev, html) {
    tip.innerHTML = html;
    tip.hidden = false;
    var r = tip.getBoundingClientRect();
    var x = ev.clientX + 14, y = ev.clientY - r.height - 12;
    if (x + r.width > window.innerWidth - 8) { x = ev.clientX - r.width - 14; }
    if (y < 8) { y = ev.clientY + 18; }
    tip.style.left = x + 'px';
    tip.style.top = y + 'px';
  }
  function hideTip() { tip.hidden = true; }
  function hover(node, html, onEnter, onLeave) {
    var enter = function (ev) { showTip(ev, html); if (onEnter) { onEnter(); } };
    node.addEventListener('mousemove', enter);
    node.addEventListener('click', enter);
    node.addEventListener('mouseleave', function () { hideTip(); if (onLeave) { onLeave(); } });
  }
  window.addEventListener('scroll', hideTip, { passive: true });

  /* line chart over the decade: one or two series, optional area, gap and notes */
  function lineChart(mount, o) {
    var W = widthOf(mount), H = 300, L = 40, R = 22, T = 26, B = 40;
    var years = D.years, n = years.length;
    function x(i) { return L + i * (W - L - R) / (n - 1); }
    function y(v) { return T + (1 - v / 10) * (H - T - B); }
    function pts(k) { return D.series[k].map(function (v, i) { return [x(i), y(v)]; }); }
    var svg = svgIn(mount, W, H, o.aria);
    if (o.band) {
      var bw = (W - L - R) / (n - 1);
      el('rect', { x: x(o.band[0]) - bw / 2, y: T - 6, width: x(o.band[1]) - x(o.band[0]) + bw, height: H - T - B + 6, rx: 10, 'class': 'band' }, svg);
    }
    [0, 5, 10].forEach(function (v) {
      el('line', { x1: L, x2: W - R, y1: y(v), y2: y(v), 'class': v === 0 ? 'base' : 'grid' }, svg);
      label(svg, L - 10, y(v) + 4, String(v), 'ax', 'end');
    });
    years.forEach(function (yr, i) { if (i % (W < 480 ? 5 : 2) === 0) { label(svg, x(i), H - 14, String(yr), 'ax'); } });
    if (o.gap) {
      var a = pts(o.gap[0]), b = pts(o.gap[1]).reverse();
      delay(el('polygon', { points: a.concat(b).map(function (p) { return p.join(','); }).join(' '), 'class': 'gap fade' }, svg), 900);
    }
    if (o.area) {
      var p0 = pts(o.series[0]);
      var d0 = 'M' + x(0) + ' ' + y(0) + ' L' + p0.map(function (p) { return p.join(' '); }).join(' L') + ' L' + x(n - 1) + ' ' + y(0) + ' Z';
      delay(el('path', { d: d0, fill: COL[o.series[0]], 'fill-opacity': 0.13, 'class': 'fade' }, svg), 700);
    }
    var xhair = el('line', { x1: 0, x2: 0, y1: T, y2: H - B, 'class': 'xhair' }, svg);
    o.series.forEach(function (k) {
      var p = pts(k);
      el('path', { d: 'M' + p.map(function (q) { return q.join(' '); }).join(' L'), stroke: COL[k], 'class': 'draw' }, svg);
      p.forEach(function (q, i) {
        delay(el('circle', { cx: q[0], cy: q[1], r: 4.5, fill: COL[k], stroke: '#FBF8F2', 'stroke-width': 2, 'class': 'fade' }, svg), 250 + i * 140);
      });
    });
    (o.labels || []).forEach(function (lb) {
      delay(label(svg, x(lb.i), y(D.series[lb.key][lb.i]) + lb.dy, D.names[lb.key], 'lbl fade'), 1500);
    });
    (o.notes || []).forEach(function (nt) {
      var v = nt.v !== undefined ? nt.v : D.series[nt.key][nt.i];
      delay(label(svg, x(nt.i) + (nt.dx || 0), y(v) + (nt.dy || 0), nt.text, 'note fade', nt.anchor || 'middle'), 1700);
    });
    var colW = (W - L - R) / (n - 1);
    years.forEach(function (yr, i) {
      var hit = el('rect', { x: x(i) - colW / 2, y: T, width: colW, height: H - T - B, fill: 'transparent' }, svg);
      var keys = o.series.concat(o.extra || []);
      var html = '<b>' + yr + '</b>' + keys.map(function (k) { return '<br>' + D.names[k] + ': ' + D.series[k][i]; }).join('');
      hover(hit, html,
        function () { xhair.setAttribute('x1', x(i)); xhair.setAttribute('x2', x(i)); xhair.style.opacity = 1; },
        function () { xhair.style.opacity = 0; });
    });
  }

  /* the whole decade as a grid: six scores x eleven years */
  function gridChart(mount) {
    var keys = ['happiness', 'achievement', 'growth', 'direction', 'heart', 'strength'];
    var W = widthOf(mount), L = 112, T = 26, g = 3;
    var cw = Math.min(44, Math.floor((W - L - 10 * g - 6) / 11)), ch = Math.min(34, cw + 10);
    var H = T + keys.length * (ch + g) + 52;
    var svg = svgIn(mount, W, H, 'Six scores for every year from 2015 to 2025. Growth stays at 8 or 9 from 2015 to 2024, then drops to 0 in 2025, the year heart reaches 10.');
    D.years.forEach(function (yr, i) { if (cw >= 26 || i % 2 === 0) { label(svg, L + i * (cw + g) + cw / 2, T - 10, "'" + String(yr).slice(2), 'ax'); } });
    keys.forEach(function (k, r) {
      var top = T + r * (ch + g);
      label(svg, L - 12, top + ch / 2 + 4, D.names[k], k === 'growth' ? 'lbl' : 'ax', 'end');
      D.series[k].forEach(function (v, i) {
        var c = el('rect', { x: L + i * (cw + g), y: top, width: cw, height: ch, rx: 6, fill: RAMP[bin(v)], 'class': 'cell' }, svg);
        delay(c, i * 85 + r * 35);
        hover(c, '<b>' + D.years[i] + '</b><br>' + D.names[k] + ': ' + v);
      });
    });
    var gy = T + 2 * (ch + g);
    delay(el('rect', { x: L - 4, y: gy - 4, width: 10 * (cw + g) + 5, height: ch + 8, rx: 10, 'class': 'ring-hl fade' }, svg), 1400);
    var ly = T + keys.length * (ch + g) + 22;
    label(svg, L - 12, ly + 11, 'Score', 'ax', 'end');
    var sp = Math.min(82, Math.floor((W - L) / 5));
    ['0-1', '2-3', '4-5', '6-7', '8-10'].forEach(function (t, b) {
      var sx = L + b * sp;
      el('rect', { x: sx, y: ly, width: sp < 60 ? 14 : 30, height: 14, rx: 4, fill: RAMP[b] }, svg);
      label(svg, sx + (sp < 60 ? 18 : 38), ly + 11, t, 'ax', 'start');
    });
  }

  /* TOPIK scores as a staircase */
  function stairsChart(mount) {
    var t = D.topik, n = t.length;
    var W = widthOf(mount), H = 280, L = 48, R = 24, T = 30, B = 42, lo = 160, hi = 250;
    var w = (W - L - R) / n;
    function y(s) { return T + (1 - (s - lo) / (hi - lo)) * (H - T - B); }
    var svg = svgIn(mount, W, H, 'TOPIK scores in 2019 climbing like stairs: 177, 194, 206, 225 and 239, passing the level 6 line at 230.');
    [160, 190, 220, 250].forEach(function (s) {
      el('line', { x1: L, x2: W - R, y1: y(s), y2: y(s), 'class': s === lo ? 'base' : 'grid' }, svg);
      label(svg, L - 10, y(s) + 4, String(s), 'ax', 'end');
    });
    el('line', { x1: L, x2: W - R, y1: y(230), y2: y(230), 'class': 'thresh' }, svg);
    label(svg, L + 4, y(230) - 8, 'Level 6 starts at 230', 'note', 'start');
    var d = 'M' + L + ' ' + y(t[0].s);
    t.forEach(function (e, i) { d += ' H' + (L + (i + 1) * w); if (i < n - 1) { d += ' V' + y(t[i + 1].s); } });
    el('path', { d: d, stroke: COL.achievement, 'class': 'draw' }, svg);
    t.forEach(function (e, i) {
      var cx = L + (i + 0.5) * w, cy = y(e.s);
      delay(el('circle', { cx: cx, cy: cy, r: 5, fill: COL.achievement, stroke: '#FBF8F2', 'stroke-width': 2, 'class': 'fade' }, svg), 300 + i * 280);
      label(svg, cx, H - 16, e.m, 'ax');
      var hit = el('rect', { x: L + i * w, y: T, width: w, height: H - T - B, fill: 'transparent' }, svg);
      hover(hit, '<b>' + e.m + ' 2019</b><br>Score ' + e.s + ', level ' + e.l);
    });
    delay(label(svg, L + 0.5 * w, y(t[0].s) - 12, String(t[0].s), 'lbl fade'), 400);
    delay(label(svg, L + (n - 0.5) * w, y(t[n - 1].s) - 12, String(t[n - 1].s), 'lbl fade'), 1700);
  }

  /* 2025: six numbers that count up */
  function bridgeChart(mount, fig) {
    var keys = ['happiness', 'achievement', 'growth', 'direction', 'heart', 'strength'];
    var last = D.years.length - 1;
    var wrap = document.createElement('div');
    wrap.className = 'bridge';
    keys.forEach(function (k) {
      var v = D.series[k][last];
      var tile = document.createElement('div');
      tile.className = 'bt' + ((k === 'heart' || k === 'strength') ? ' hl' : '');
      tile.innerHTML = '<span class="k">' + D.names[k] + '</span><span class="v" data-v="' + v + '">' + (reduce ? v : 0) + '</span>';
      wrap.appendChild(tile);
    });
    mount.appendChild(wrap);
    fig._onIn = function () {
      if (reduce) { return; }
      var start = null, nodes = wrap.querySelectorAll('.v');
      function step(ts) {
        if (!start) { start = ts; }
        var p = Math.min(1, (ts - start) / 1500), e = 1 - Math.pow(1 - p, 3);
        Array.prototype.forEach.call(nodes, function (nd) { nd.textContent = Math.round(e * Number(nd.getAttribute('data-v'))); });
        if (p < 1) { window.requestAnimationFrame(step); }
      }
      window.requestAnimationFrame(step);
    };
  }

  var builders = {
    landscape: function (m) {
      lineChart(m, { series: ['happiness'], area: true,
        aria: 'Happiness from 2015 to 2025: 7, 7, 9, 8, 3, 2, 4, 3, 6, 6 and 0.',
        notes: [
          { key: 'happiness', i: 2, dy: -16, text: 'Peak at 22: 9' },
          { key: 'happiness', i: 5, dy: 24, text: 'Valley: 2' },
          { key: 'happiness', i: 10, dy: -6, dx: -16, text: 'Thirty: 0', anchor: 'end' }
        ] });
    },
    grid: function (m) { gridChart(m); },
    scoreboards: function (m) {
      lineChart(m, { series: ['achievement', 'growth'], gap: ['growth', 'achievement'],
        aria: 'Achievement and growth from 2015 to 2025. From 2020 to 2022 achievement was 2 while growth was 9.',
        labels: [{ key: 'growth', i: 6, dy: -14 }, { key: 'achievement', i: 6, dy: 24 }],
        notes: [{ i: 6, v: 5.6, text: 'The gap nobody saw' }] });
    },
    roads: function (m) {
      lineChart(m, { series: ['direction', 'growth'], gap: ['growth', 'direction'],
        aria: 'Growth and direction from 2015 to 2025. Direction falls from 10 at age 22 to 3 at age 29 while growth stays at 9.',
        labels: [{ key: 'growth', i: 7, dy: -14 }, { key: 'direction', i: 7, dy: 24 }],
        notes: [{ i: 9, v: 6, dy: 4, dx: -10, text: '+6', anchor: 'end' }, { key: 'direction', i: 2, dy: -14, text: 'Certain: 10' }] });
    },
    strength: function (m) {
      lineChart(m, { series: ['strength'], area: true,
        aria: 'Inner strength from 2015 to 2025: 8, 8, 8, 6, 3, 2, 2, 3, 4, 5 and 6.',
        notes: [
          { key: 'strength', i: 0, dy: -14, text: '8, untested', anchor: 'start' },
          { key: 'strength', i: 5, dy: 24, text: '2, broken' },
          { key: 'strength', i: 10, dy: -14, text: '6, and it held', anchor: 'end' }
        ] });
    },
    period: function (m, f) {
      var a = Number(f.getAttribute('data-from')), b = Number(f.getAttribute('data-to'));
      lineChart(m, { series: ['achievement', 'growth'], band: [a, b],
        aria: 'Achievement and growth across my twenties, with ' + D.years[a] + (b > a ? ' to ' + D.years[b] : '') + ' highlighted.',
        notes: [{ i: (a + b) / 2, v: 10, dy: -12, text: 'This chapter' }] });
    },
    topik: function (m) { stairsChart(m); },
    bridge: function (m, f) { bridgeChart(m, f); }
  };

  function reveal(f) { f.classList.add('in'); if (f._onIn) { f._onIn(); } }
  var io = (!reduce && 'IntersectionObserver' in window) ? new IntersectionObserver(function (entries) {
    entries.forEach(function (en) { if (en.isIntersecting) { reveal(en.target); io.unobserve(en.target); } });
  }, { threshold: 0.3 }) : null;

  Array.prototype.forEach.call(document.querySelectorAll('[data-chart]'), function (f) {
    var build = builders[f.getAttribute('data-chart')], m = f.querySelector('.chart-mount');
    if (!build || !m) { return; }
    build(m, f);
    Array.prototype.forEach.call(f.querySelectorAll('.draw'), function (p) { p.style.setProperty('--len', Math.ceil(p.getTotalLength())); });
    f.classList.add('js');
    if (io) { io.observe(f); } else { reveal(f); }
  });
})();
