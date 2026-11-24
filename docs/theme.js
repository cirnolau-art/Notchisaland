const picker = document.querySelector('#theme');
const themeKey = 'notchisland-pages-theme';

function setTheme(theme) {
  const value = ['light', 'dark'].includes(theme) ? theme : 'system';
  if (value === 'system') {
    document.documentElement.removeAttribute('data-theme');
  } else {
    document.documentElement.dataset.theme = value;
  }
  picker.value = value;
}

try {
  setTheme(localStorage.getItem(themeKey));
} catch {
  setTheme('system');
}

picker.closest('.theme').hidden = false;
picker.addEventListener('change', () => {
  setTheme(picker.value);
  try {
    localStorage.setItem(themeKey, picker.value);
  } catch {
    // The current page can still change appearance when storage is unavailable.
  }
});
