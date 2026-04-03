document$.subscribe(function () {
  function setupMermaidZoom() {
    document.querySelectorAll('.mermaid svg').forEach(function (svg) {
      if (svg.dataset.zoomReady) return;
      svg.dataset.zoomReady = 'true';

      svg.addEventListener('click', function () {
        var overlay = document.createElement('div');
        overlay.className = 'mermaid-zoom-overlay';

        var wrapper = document.createElement('div');
        wrapper.className = 'mermaid-zoom-wrapper';

        var clone = svg.cloneNode(true);
        clone.removeAttribute('data-zoom-ready');
        clone.style.cursor = 'default';
        clone.style.width = 'auto';
        clone.style.height = 'auto';
        clone.style.maxWidth = '85vw';
        clone.style.maxHeight = '85vh';

        wrapper.appendChild(clone);
        overlay.appendChild(wrapper);

        function close() {
          if (document.body.contains(overlay)) {
            document.body.removeChild(overlay);
          }
          document.removeEventListener('keydown', onKeyDown);
        }

        overlay.addEventListener('click', function (e) {
          if (e.target === overlay) close();
        });

        function onKeyDown(e) {
          if (e.key === 'Escape') close();
        }
        document.addEventListener('keydown', onKeyDown);

        document.body.appendChild(overlay);
      });
    });
  }

  /* Poll until Mermaid finishes rendering (async) */
  var attempts = 0;
  var timer = setInterval(function () {
    if (document.querySelectorAll('.mermaid svg').length > 0) {
      setupMermaidZoom();
      clearInterval(timer);
    } else if (++attempts >= 30) {
      clearInterval(timer);
    }
  }, 200);
});
