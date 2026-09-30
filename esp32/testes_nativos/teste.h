#pragma once
// Mini arcabouco de teste: TESTE(nome) { ... CONFERE(cond); } e main() pronto.
#include <cstdio>
#include <functional>
#include <vector>

struct Teste { const char* nome; std::function<void()> corpo; };
inline std::vector<Teste>& testes() { static std::vector<Teste> t; return t; }
inline int falhasDoTeste = 0, falhasTotais = 0;

struct Registro { Registro(const char* n, std::function<void()> f) { testes().push_back({n, f}); } };
#define TESTE_JUNTAR2(a, b) a##b
#define TESTE_JUNTAR(a, b) TESTE_JUNTAR2(a, b)
#define TESTE(nome) \
  static void TESTE_JUNTAR(teste_, __LINE__)(); \
  static Registro TESTE_JUNTAR(registro_, __LINE__)(nome, TESTE_JUNTAR(teste_, __LINE__)); \
  static void TESTE_JUNTAR(teste_, __LINE__)()

#define CONFERE(cond) do { if (!(cond)) { ++falhasDoTeste; \
  std::printf("    falhou: %s (%s:%d)\n", #cond, __FILE__, __LINE__); } } while (0)
#define PERTO(valor, esperado, tolerancia) do { const double v_ = (valor), e_ = (esperado); \
  if (!(v_ >= e_ - (tolerancia) && v_ <= e_ + (tolerancia))) { ++falhasDoTeste; \
  std::printf("    falhou: %s = %.4f, esperado %.4f +/- %.4f (%s:%d)\n", #valor, v_, e_, \
              (double)(tolerancia), __FILE__, __LINE__); } } while (0)

int main() {
  for (const Teste& t : testes()) {
    falhasDoTeste = 0;
    t.corpo();
    std::printf("%s %s\n", falhasDoTeste ? "FALHOU" : "ok    ", t.nome);
    falhasTotais += falhasDoTeste ? 1 : 0;
  }
  std::printf("%zu testes, %d falharam\n", testes().size(), falhasTotais);
  return falhasTotais ? 1 : 0;
}
