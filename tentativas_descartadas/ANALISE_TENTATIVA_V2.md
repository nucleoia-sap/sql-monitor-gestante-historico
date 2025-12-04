# Análise: Tentativa V2 - Agrupamento por Data de Atendimento

**Data**: 03/12/2025
**Status**: ❌ Descartado - Voltamos para V1
**Motivo**: Fragmentação excessiva de gestações

---

## 🎯 Objetivo da V2

Corrigir o problema de **id_hci duplicados** (atendimentos médicos aparecendo em múltiplas gestações) usando agrupamento temporal por **data do atendimento** em vez da **DUM registrada**.

## 📊 Resultados Comparativos

| Métrica | V1 (Original) | V2 (Tentativa) | Diferença |
|---------|---------------|----------------|-----------|
| Total gestações | **28,780** ✅ | 81,460 ❌ | **+183%** |
| Pacientes únicos | 28,293 | 68,721 | +143% |
| id_hci duplicados | 13 | 1 | -12 ✅ |
| Pacientes com 2 gestações | 477 | 9,686 | +1,929% |
| Pacientes com 3+ gestações | 5 | 1,498 | +29,860% |
| Máximo gest/paciente | 3 | 4 | +1 |

## ❌ Por Que V2 Falhou

### Problema Central: Fragmentação de Gestações

**Cenário Real**:
```
Gestação Única com Acompanhamento Espaçado:
- Atendimento 1 (01/jan/2025): DUM = 15/out/2024
- Atendimento 2 (15/mar/2025, 73 dias depois): DUM = 15/out/2024 (mesma!)

V1 (DUM): 1 gestação ✅ (DUM é idêntica = mesma gestação)
V2 (data_atendimento): 2 gestações ❌ (atendimentos > 60 dias = separou incorretamente)
```

### Por Que Isso Acontece

1. **Gestantes com acompanhamento irregular**: Podem ter consultas espaçadas por mais de 60 dias
2. **DUM permanece constante**: Mesmo com atendimentos espaçados, a DUM não muda
3. **V2 interpreta como gestações diferentes**: Janela de 60 dias entre atendimentos cria fragmentação artificial

### Casos Problemáticos na V2

- **Alto risco com internações**: Paciente interna, fica sem consultas ambulatoriais por 2-3 meses, volta com mesma DUM
- **Faltas e remarcações**: Paciente falta consultas, retorna após >60 dias, mesma gestação
- **Mudança de unidade**: Paciente muda de clínica, >60 dias entre último atendimento na antiga e primeiro na nova

## ✅ Por Que V1 É Correta

### Lógica de Agrupamento por DUM

**Princípio Clínico**:
- A DUM define o início da gestação
- Atendimentos espaçados não criam nova gestação se DUM permanece igual
- Diferenças > 60 dias na DUM indicam **correção significativa** → possível nova gestação

**Regra dos 60 dias aplicada à DUM**:
```sql
-- V1: Compara DUMs registradas
WHEN DATE_DIFF(data_evento, LAG(data_evento), DAY) > 60 THEN nova_gestacao_flag = 1

Interpretação:
- DUM corrigida por >60 dias = nova gestação (provavelmente gestação diferente confundida)
- DUM constante com atendimentos espaçados = mesma gestação ✅
```

## 📌 Conclusão: id_hci Duplicados São Aceitáveis

### Análise dos 13 Casos

**V1 apresenta 13 casos** de id_hci em múltiplas gestações em 28.780 gestações = **0.045%**

**Cenários Esperados**:
1. **Gestações sequenciais muito próximas**: Aborto seguido de nova gestação em <60 dias
2. **Correções retroativas**: Sistema corrige DUM retroativamente, criando ambiguidade
3. **Erro de registro**: Mesmo episódio clínico registrado com CIDs de gestações diferentes

### Por Que É Aceitável

- **Taxa baixíssima**: 0.045% não afeta análises agregadas
- **Complexidade clínica real**: Casos limítrofes existem na prática
- **Trade-off**: Melhor aceitar 13 casos ambíguos do que criar 52.680 gestações fictícias

## 🎓 Lições Aprendidas

### 1. Agrupamento Temporal Deve Seguir Lógica Clínica
- **DUM é o marcador correto** para agrupar gestações
- **Data de atendimento** não reflete continuidade da gestação

### 2. Validação de Números Absolutos
- **28.000 gestações** é o esperado para a janela de 340 dias
- **80.000+ gestações** é claramente anômalo
- Sempre comparar com baseline conhecido

### 3. Trade-offs São Necessários
- **Perfeição no id_hci** (1 duplicado) vs **Fragmentação massiva** (53K gestações extras)
- **Aceitar 13 duplicados** (0.045%) é razoável

## 📂 Arquivos Relacionados

- **Solução Oficial**: `1_gestacoes_historico.sql` (V1)
- **Tentativa Descartada**: `1_gestacoes_historico_v2.sql` (arquivado)
- **Script de Comparação**: `teste_v1_vs_v2.sql`
- **Investigação Inicial**: `investigacao_agrupamento.sql`

## ✅ Decisão Final

**Manter V1 como solução oficial**:
- ✅ 28.780 gestações (número esperado)
- ✅ Lógica clinicamente correta (agrupamento por DUM)
- ✅ 13 id_hci duplicados aceitáveis (0.045%)
- ✅ Validado contra padrões conhecidos

---

**Autor**: Claude Code
**Revisado por**: Usuário (confirmação de número esperado ~28.000)
**Status**: Análise completa - V1 aprovada
