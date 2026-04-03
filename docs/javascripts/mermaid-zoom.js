(function () {
  function openZoomModal(svg) {
    var overlay = document.createElement('div');
    overlay.className = 'mermaid-zoom-overlay';

    var wrapper = document.createElement('div');
    wrapper.className = 'mermaid-zoom-wrapper';

    var closeBtn = document.createElement('button');
    closeBtn.className = 'mermaid-zoom-close';
    closeBtn.setAttribute('aria-label', 'Close');
    closeBtn.innerHTML = '&times;';

    var clone = svg.cloneNode(true);
    clone.removeAttribute('data-zoom-ready');
    clone.style.cursor = 'default';
    clone.style.width = '100%';
    clone.style.height = '100%';

    wrapper.appendChild(closeBtn);
    wrapper.appendChild(clone);
    overlay.appendChild(wrapper);

    function close() {
      if (document.body.contains(overlay)) {
        document.body.removeChild(overlay);
      }
      document.removeEventListener('keydown', onKeyDown);
    }

    closeBtn.addEventListener('click', close);
    overlay.addEventListener('click', function (e) {
      if (e.target === overlay) close();
    });

    function onKeyDown(e) {
      if (e.key === 'Escape') close();
    }
    document.addEventListener('keydown', onKeyDown);

    document.body.appendChild(overlay);

    if (typeof svgPanZoom !== 'undefined') {
      svgPanZoom(clone, {
        zoomEnabled: true,
        controlIconsEnabled: true,
        fit: true,
        center: true,
        minZoom: 0.1,
        maxZoom: 10
      });
    }
  }

  function setupMermaidZoom() {
    document.querySelectorAll('.mermaid svg').forEach(function (svg) {
      if (svg.dataset.zoomReady) return;
      svg.dataset.zoomReady = 'true';
      svg.addEventListener('click', function () {
        openZoomModal(svg);
      });
    });
  }

  function pollForMermaid() {
    var attempts = 0;
    var timer = setInterval(function () {
      if (document.querySelectorAll('.mermaid svg').length > 0) {
        setupMermaidZoom();
        clearInterval(timer);
      } else if (++attempts >= 30) {
        clearInterval(timer);
      }
    }, 200);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', pollForMermaid);
  } else {
    pollForMermaid();
  }

  if (typeof document$ !== 'undefined') {
    document$.subscribe(pollForMermaid);
  }
}());
