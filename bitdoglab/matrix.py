"""Matriz 5x5 WS2812 da BitDogLab: icones e barras com brilho baixo."""
import neopixel
from machine import Pin

# Indice do LED para (linha, coluna), linha 0 em cima. Ligacao em serpentina
# da BitDogLab v6.3, comecando no canto inferior direito.
MAP = (
    (24, 23, 22, 21, 20),
    (15, 16, 17, 18, 19),
    (14, 13, 12, 11, 10),
    (5, 6, 7, 8, 9),
    (4, 3, 2, 1, 0),
)

GREEN = (0, 255, 0)
YELLOW = (255, 160, 0)
RED = (255, 0, 0)
BLUE = (0, 80, 255)
CYAN = (0, 200, 200)
WHITE = (255, 255, 255)

# Icones 5x5 ("#" aceso).
ICONS = {
    "play": ("#....", "###..", "#####", "###..", "#...."),
    "stop": (".....", ".###.", ".###.", ".###.", "....."),
    "alert": ("..#..", "..#..", "..#..", ".....", "..#.."),
    "star": ("#...#", ".#.#.", "..#..", "..#..", "..#.."),
    "delta": ("..#..", ".#.#.", ".#.#.", "#...#", "#####"),
    "dash": (".....", ".....", "#####", ".....", "....."),
    "off": ("#...#", ".#.#.", "..#..", ".#.#.", "#...#"),
}


class Matrix:
    def __init__(self, pin, brightness=0.04, flip=False):
        self.np = neopixel.NeoPixel(Pin(pin), 25)
        self.level = brightness
        self.flip = flip
        self.last = None

    def _scale(self, color):
        return tuple(int(c * self.level) for c in color)

    def _set(self, r, c, color):
        if self.flip:
            r, c = 4 - r, 4 - c
        self.np[MAP[r][c]] = color

    def _write(self, key):
        # So escreve quando muda: evita tremulacao e trafego no barramento.
        if key != self.last:
            self.last = key
            self.np.write()

    def clear(self):
        self.np.fill((0, 0, 0))
        self._write("clear")

    def icon(self, name, color):
        rows = ICONS[name]
        col = self._scale(color)
        self.np.fill((0, 0, 0))
        for r in range(5):
            for c in range(5):
                if rows[r][c] == "#":
                    self._set(r, c, col)
        self._write(("icon", name, color))

    def bar(self, fraction, label_color=None):
        """Nivel de 0 a 5 LEDs so na linha de baixo: verde, amarelo e vermelho.

        fraction 1.0 = nominal/limite (4 LEDs); acima disso acende o 5o.
        """
        if fraction is None:
            self.icon("dash", WHITE)
            return
        cols = 0 if fraction <= 0.02 else min(5, int(fraction * 4 + 0.999))
        self.np.fill((0, 0, 0))
        for c in range(cols):
            color = GREEN if c < 3 else (YELLOW if c == 3 else RED)
            self._set(4, c, self._scale(color))
        self._write(("bar", cols))
