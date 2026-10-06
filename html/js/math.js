(function (root) {
  'use strict';
  const clamp = (n, min, max) => Math.min(max, Math.max(min, n));
  function place(position, size, viewport, margin = 0) {
    const edge = typeof margin === 'number' ? { left: margin, right: margin, top: margin, bottom: margin } : margin;
    const x = clamp(position.x * viewport.width, edge.left, Math.max(edge.left, viewport.width - size.width - edge.right));
    const y = clamp(position.y * viewport.height, edge.top, Math.max(edge.top, viewport.height - size.height - edge.bottom));
    return { x: x / viewport.width, y: y / viewport.height, scale: position.scale };
  }
  function drag(pointer, offset, size, viewport, scale, margin, snap = 0) {
    const quantize = (n, total) => snap ? Math.round(n / total / snap) * total * snap : n;
    return place({
      x: quantize(pointer.x - offset.x, viewport.width) / viewport.width,
      y: quantize(pointer.y - offset.y, viewport.height) / viewport.height,
      scale
    }, size, viewport, margin);
  }
  const api = { clamp, place, drag };
  if (typeof module !== 'undefined') module.exports = api;
  else root.HudLayoutMath = api;
})(typeof window === 'undefined' ? globalThis : window);
