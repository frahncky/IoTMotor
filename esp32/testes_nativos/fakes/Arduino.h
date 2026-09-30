#pragma once
// Arduino de mentira para compilar os cabecalhos do firmware no PC (g++).
// So o que os modulos testados usam: millis, Serial, String e digitalWrite.
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <math.h>
#include <string>

using std::isfinite;

inline unsigned long relogioFalsoMs = 0;
inline unsigned long millis() { return relogioFalsoMs; }

class String {
 public:
  String(const char* texto = "") : s_(texto ? texto : "") {}
  String(const std::string& texto) : s_(texto) {}
  const char* c_str() const { return s_.c_str(); }
  unsigned int length() const { return static_cast<unsigned int>(s_.size()); }
  bool concat(const char* texto) { s_ += texto; return true; }
  bool concat(char c) { s_ += c; return true; }
  bool reserve(unsigned int n) { s_.reserve(n); return true; }
  String& operator+=(const char* texto) { s_ += texto; return *this; }
  String& operator+=(const String& outro) { s_ += outro.s_; return *this; }
  bool operator==(const char* texto) const { return s_ == texto; }
  bool operator==(const String& outro) const { return s_ == outro.s_; }
  char operator[](unsigned int i) const { return s_[i]; }

 private:
  std::string s_;
};

struct SerialFalso {
  void printf(const char*, ...) {}
  void println(const char* = "") {}
  void print(const char*) {}
};
inline SerialFalso Serial;

constexpr uint8_t HIGH = 1, LOW = 0;
