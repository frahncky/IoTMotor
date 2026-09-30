#pragma once
// I2C de mentira: os testes da vibracao alimentam vibracao::amostra() direto,
// sem passar pela FIFO do MPU6050.
#include "Arduino.h"

struct WireFalso {
  void beginTransmission(uint8_t) {}
  size_t write(uint8_t) { return 1; }
  uint8_t endTransmission(bool = true) { return 0; }
  uint8_t requestFrom(uint8_t, uint8_t n, uint8_t = 1) { return n; }
  int read() { return 0; }
};
inline WireFalso Wire;
