// Documentation page shared scripts
// - Highlight.js initialization
// - toggleSurprise helper
// - Audio player handlers

// Initialize code highlighting (requires highlight.js loaded in the page)
if (typeof hljs !== 'undefined' && hljs.highlightAll) {
  hljs.highlightAll();
}

function toggleSurprise(element) {
  const hiddenContent = element.querySelector('.hidden-content');
  if (!hiddenContent) return;
  if (hiddenContent.style.display === 'none' || hiddenContent.style.display === '') {
    hiddenContent.style.display = 'inline';
  } else {
    hiddenContent.style.display = 'none';
  }
}

// Audio player handlers
// All audio files present in `sfx/` will be rendered as native audio controls.
const SFX_FILES = [
  'bloop.wav',
  'dragon_fly_launch.wav',
  'firecracker.wav',
  'gameplay_BGM.mp3',
  'gong.wav',
  'Menu_BGM.mp3',
  'party_popper_launch.wav',
  'scooter_sfx.wav',
  'swipe.wav',
  'yay_cheer.mp3'
];

document.addEventListener('DOMContentLoaded', function () {
  // Initialize collapsible sections
  (function initCollapsibles() {
    const sections = document.querySelectorAll('.documentation-section');
    sections.forEach((section) => {
      // Keep the introduction section always expanded
      if (section.id === 'introduction') {
        const content = section.querySelector('.section-content');
        if (content) {
          content.style.overflow = '';
          content.style.maxHeight = 'none';
        }
        section.classList.remove('collapsed');
        return; // skip making it collapsible
      }
      const header = section.querySelector('.section-header');
      const content = section.querySelector('.section-content');
      if (!header || !content) return;

      header.classList.add('collapsible-header');

      const btn = document.createElement('button');
      btn.className = 'section-toggle';
      btn.setAttribute('aria-expanded', 'true');
      btn.setAttribute('aria-label', 'Toggle section');
      btn.innerHTML = '▾';

      // insert toggle button at the start of the header
      header.insertBefore(btn, header.firstChild);

      // set initial max-height for smooth transitions
      content.style.overflow = 'hidden';
      content.style.transition = 'max-height 280ms ease';
      // start collapsed by default
      content.style.maxHeight = '0';
      btn.setAttribute('aria-expanded', 'false');
      btn.innerHTML = '▸';
      section.classList.add('collapsed');

      function collapse() {
        btn.setAttribute('aria-expanded', 'false');
        section.classList.add('collapsed');
        content.style.maxHeight = '0';
        btn.innerHTML = '▸';
      }

      function expand() {
        btn.setAttribute('aria-expanded', 'true');
        section.classList.remove('collapsed');
        content.style.maxHeight = content.scrollHeight + 'px';
        btn.innerHTML = '▾';
      }

      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        const expanded = btn.getAttribute('aria-expanded') === 'true';
        if (expanded) collapse(); else expand();
      });

      // allow clicking the header to toggle as well
      header.addEventListener('click', function (e) {
        if (e.target === btn) return;
        btn.click();
      });

      // adjust maxHeight on window resize when expanded
      window.addEventListener('resize', function () {
        if (btn.getAttribute('aria-expanded') === 'true') {
          content.style.maxHeight = content.scrollHeight + 'px';
        }
      });
    });
  })();
  const sfxListContainer = document.getElementById('sfx-list');

  // Build SFX native audio controls for every file in SFX_FILES
  if (sfxListContainer && Array.isArray(SFX_FILES)) {
    const audioElements = [];

    SFX_FILES.forEach((file) => {
      const row = document.createElement('div');
      row.className = 'sfx-row';
      row.style.display = 'flex';
      row.style.alignItems = 'center';
      row.style.gap = '12px';
      row.style.marginBottom = '12px';

      const label = document.createElement('div');
      label.textContent = file;
      label.style.minWidth = '180px';
      label.style.fontSize = '14px';
      label.style.color = 'var(--muted, #666)';

      // Create native audio element with controls
      const audio = document.createElement('audio');
      audio.controls = true;
      audio.setAttribute('controlsList', 'nodownload');
      audio.preload = 'none';
      audio.src = 'sfx/' + file;
      audio.style.flex = '1';

      // When one audio starts playing, pause all others
      audio.addEventListener('play', function () {
        audioElements.forEach((a) => {
          if (a !== audio) {
            try { a.pause(); } catch (e) { }
          }
        });
      });

      audioElements.push(audio);

      row.appendChild(label);
      row.appendChild(audio);

      sfxListContainer.appendChild(row);
    });
  }
});
