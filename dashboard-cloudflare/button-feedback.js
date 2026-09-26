(() => {
  'use strict';

  document.addEventListener('click', (event) => {
    const button = event.target.closest('button');
    if (!button || button.disabled) return;

    // Reinicia a animação mesmo em cliques consecutivos rápidos.
    button.classList.remove('button-clicked');
    void button.offsetWidth;
    button.classList.add('button-clicked');

    const clear = () => {
      button.classList.remove('button-clicked');
      button.removeEventListener('animationend', clear);
    };
    button.addEventListener('animationend', clear);

    // Fallback para navegadores que não disparam animationend.
    setTimeout(() => button.classList.remove('button-clicked'), 260);
  });
})();