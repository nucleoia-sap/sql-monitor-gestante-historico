# Regras Definitivas V3 - Histórico de Gestações

## 📋 Especificação Formal

### Regra 1: Filtro Temporal de Gestações

```
Incluir gestação SE E SOMENTE SE:
    data_inicio <= data_referencia
```

**Justificativa Conceitual**:
- Um snapshot em `data_referencia` deve mostrar gestações que **já existiam** naquela data
- Gestações futuras (`data_inicio > data_referencia`) não são relevantes para aquele momento

**Exemplo**:
```
data_referencia = 2024-10-31

✅ Incluir: data_inicio = 2024-08-15 (começou antes do snapshot)
✅ Incluir: data_inicio = 2024-10-31 (começou no dia do snapshot)
❌ Excluir: data_inicio = 2024-11-05 (começou depois do snapshot)
```

### Regra 2: Classificação de Fase Atual

#### Fase: **Gestação**
```
Condição: data_inicio <= data_referencia <= data_fim
        OU (data_fim IS NULL E data_referencia < data_inicio + 299 dias)
```

**Interpretação**:
- Gestação está **em curso** na data_referencia
- Início já ocorreu, fim ainda não aconteceu
- Se sem data_fim, protege auto-encerramento após 299 dias

**Exemplos**:
```
data_referencia = 2024-10-31

✅ Gestação: data_inicio = 2024-08-15, data_fim = NULL
   → Em curso, 11 semanas de gestação

✅ Gestação: data_inicio = 2024-06-01, data_fim = 2024-11-15
   → Em curso, 22 semanas, ainda não terminou

❌ Não Gestação: data_inicio = 2024-01-10, data_fim = 2024-10-01
   → Já terminou (fim < data_referencia)
```

#### Fase: **Puerpério**
```
Condição: data_fim < data_referencia <= (data_fim + 42 dias)
```

**Interpretação**:
- Gestação já terminou
- Está dentro da janela de puerpério (0-42 dias pós-parto)
- Puerpério MS: 6 semanas = 42 dias

**Exemplos**:
```
data_referencia = 2024-10-31

✅ Puerpério: data_fim = 2024-10-25 (6 dias atrás)
   → Puerpério recente

✅ Puerpério: data_fim = 2024-09-20 (41 dias atrás)
   → Ainda dentro da janela de 42 dias

❌ Não Puerpério: data_fim = 2024-09-15 (46 dias atrás)
   → Passou da janela de 42 dias
```

#### Fase: **Encerrada**
```
Condição: data_referencia > (data_fim + 45 dias)
```

**Interpretação**:
- Gestação terminou há mais de 45 dias
- Puerpério já passou
- **ESTA FASE NÃO É INCLUÍDA NO SNAPSHOT**

**Exemplos**:
```
data_referencia = 2024-10-31

✅ Encerrada: data_fim = 2024-08-15 (77 dias atrás)
   → Mas será EXCLUÍDA do snapshot

✅ Encerrada: data_fim = 2024-01-20 (284 dias atrás)
   → Mas será EXCLUÍDA do snapshot
```

#### ⚠️ Gap: Entre 42 e 45 dias

**Observação**: Há uma **janela de transição** de 3 dias entre o fim do puerpério e o início da fase "Encerrada":

```
data_fim + 42 dias < data_referencia <= data_fim + 45 dias
```

**Tratamento na implementação**:
- Classificadas como `'Em transição'`
- Também são **EXCLUÍDAS** do snapshot (não são Gestação nem Puerpério)

**Exemplo**:
```
data_referencia = 2024-10-31
data_fim = 2024-09-18

Cálculo:
- data_fim + 42 dias = 2024-10-30
- data_fim + 45 dias = 2024-11-02

Status: data_referencia (10-31) está entre 10-30 e 11-02
→ fase_atual = 'Em transição'
→ EXCLUÍDA do snapshot
```

### Regra 3: Exclusão de Gestações Encerradas

```
Snapshot contém APENAS:
    fase_atual IN ('Gestação', 'Puerpério')

Snapshot NÃO contém:
    fase_atual IN ('Encerrada', 'Em transição')
```

**Justificativa**:
- Gestações encerradas não são relevantes para análise do ponto temporal
- Snapshot deve representar apenas o que estava **ativo** naquela data

---

## 📊 Diagrama de Estados

```
Timeline →

Início                                 Fim                          +42d    +45d
  │                                     │                             │       │
  ├─────────────────────────────────────┤─────────────────────────────┼───────┼──────→
  │                                     │                             │       │
  │          GESTAÇÃO                   │        PUERPÉRIO            │  Gap  │  ENCERRADA
  │       (0-299 dias)                  │        (0-42 dias)          │ (3d)  │  (> 45 dias)
  │                                     │                             │       │
  │                                     │                             │       │
  ✅ Incluir no snapshot                ✅ Incluir no snapshot        ❌      ❌ Excluir


Onde está data_referencia?
├─ Dentro de Gestação → fase_atual = 'Gestação' → ✅ INCLUIR
├─ Dentro de Puerpério → fase_atual = 'Puerpério' → ✅ INCLUIR
├─ Dentro do Gap (42-45d) → fase_atual = 'Em transição' → ❌ EXCLUIR
└─ Após 45 dias → fase_atual = 'Encerrada' → ❌ EXCLUIR
```

---

## 🧪 Casos de Teste

### Caso 1: Gestação em Curso

```sql
-- Entrada
data_referencia = DATE('2024-10-31')
data_inicio = DATE('2024-08-15')
data_fim = NULL

-- Processamento
data_inicio (08-15) <= data_referencia (10-31) ✅
data_fim IS NULL ✅
data_inicio + 299 dias = 2025-06-10 > data_referencia ✅

-- Resultado
fase_atual = 'Gestação'
ig_atual_semanas = 11
trimestre = '1º trimestre'
INCLUÍDA no snapshot ✅
```

### Caso 2: Puerpério Recente

```sql
-- Entrada
data_referencia = DATE('2024-10-31')
data_inicio = DATE('2024-03-01')
data_fim = DATE('2024-10-25')  -- Parto 6 dias atrás

-- Processamento
data_fim (10-25) < data_referencia (10-31) ✅
data_fim + 42 dias = 2024-12-06 >= data_referencia ✅

-- Resultado
fase_atual = 'Puerpério'
ig_final_semanas = 34
tipo_desfecho = 'parto'
INCLUÍDA no snapshot ✅
```

### Caso 3: Puerpério Limite (42 dias)

```sql
-- Entrada
data_referencia = DATE('2024-10-31')
data_inicio = DATE('2024-02-10')
data_fim = DATE('2024-09-20')  -- Parto 41 dias atrás

-- Processamento
data_fim (09-20) < data_referencia (10-31) ✅
data_fim + 42 dias = 2024-11-01 >= data_referencia (10-31) ✅

-- Resultado
fase_atual = 'Puerpério'
INCLUÍDA no snapshot ✅
```

### Caso 4: Gap de Transição (43 dias)

```sql
-- Entrada
data_referencia = DATE('2024-10-31')
data_inicio = DATE('2024-02-08')
data_fim = DATE('2024-09-18')  -- Parto 43 dias atrás

-- Processamento
data_fim + 42 dias = 2024-10-30 < data_referencia ✅
data_fim + 45 dias = 2024-11-02 >= data_referencia ✅

-- Resultado
fase_atual = 'Em transição'
EXCLUÍDA do snapshot ❌
```

### Caso 5: Encerrada (46 dias)

```sql
-- Entrada
data_referencia = DATE('2024-10-31')
data_inicio = DATE('2024-02-05')
data_fim = DATE('2024-09-15')  -- Parto 46 dias atrás

-- Processamento
data_fim + 45 dias = 2024-10-30 < data_referencia ✅

-- Resultado
fase_atual = 'Encerrada'
EXCLUÍDA do snapshot ❌
```

### Caso 6: Gestação Futura

```sql
-- Entrada
data_referencia = DATE('2024-10-31')
data_inicio = DATE('2024-11-05')  -- Começa no futuro
data_fim = NULL

-- Processamento
data_inicio (11-05) > data_referencia (10-31) ❌
FILTRADA antes de classificar fase

-- Resultado
NÃO APARECE no processamento
Gestação não existe no snapshot ❌
```

### Caso 7: Gestação Auto-Encerrada

```sql
-- Entrada
data_referencia = DATE('2024-10-31')
data_inicio = DATE('2024-01-10')
data_fim = NULL  -- Sem evento de desfecho registrado

-- Processamento
data_inicio + 299 dias = 2024-10-06 < data_referencia ✅
data_fim IS NULL mas passou 299 dias

-- Resultado
fase_atual = 'Encerrada'
data_fim_efetiva = 2024-10-06 (auto-encerramento)
EXCLUÍDA do snapshot ❌
```

---

## 📈 Impacto no Volume de Dados

### Comparação de Versões

**V1 (Original - CID RESOLVIDO + Todas as gestações)**:
```
Snapshot 2024-10-31:
- Total: 250,000 gestações
- Gestação: 45,000
- Puerpério: 8,000
- Encerrada: 197,000 ⚠️ (não deveriam estar)
```

**V3 (Final - Eventos Desfecho + Apenas Gestação/Puerpério)**:
```
Snapshot 2024-10-31:
- Total: 53,000 gestações
- Gestação: 45,000
- Puerpério: 8,000
- Encerrada: 0 ✅ (excluídas)
```

**Redução**: ~80% no volume (de 250K para 53K)

---

## 🔍 Validações SQL

### Validação 1: Nenhuma Gestação Encerrada

```sql
-- Não deve retornar linhas
SELECT
    fase_atual,
    COUNT(*) AS total
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2024-10-31')
  AND fase_atual NOT IN ('Gestação', 'Puerpério')
GROUP BY fase_atual;

-- Resultado esperado: 0 linhas
```

### Validação 2: Todas as Gestações Iniciaram Antes

```sql
-- Não deve retornar linhas
SELECT
    COUNT(*) AS gestacoes_futuras
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2024-10-31')
  AND data_inicio > DATE('2024-10-31');

-- Resultado esperado: 0 gestacoes_futuras
```

### Validação 3: Fase Gestação Dentro dos Limites

```sql
-- Todas as gestações em fase 'Gestação' devem satisfazer a condição
SELECT
    COUNT(*) AS gestacoes_invalidas
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2024-10-31')
  AND fase_atual = 'Gestação'
  AND NOT (
      data_inicio <= DATE('2024-10-31')
      AND (data_fim IS NULL OR data_fim >= DATE('2024-10-31'))
      AND DATE_ADD(data_inicio, INTERVAL 299 DAY) >= DATE('2024-10-31')
  );

-- Resultado esperado: 0 gestacoes_invalidas
```

### Validação 4: Fase Puerpério Dentro dos Limites

```sql
-- Todas as gestações em fase 'Puerpério' devem satisfazer a condição
SELECT
    COUNT(*) AS puerperio_invalido
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2024-10-31')
  AND fase_atual = 'Puerpério'
  AND NOT (
      data_fim IS NOT NULL
      AND data_fim < DATE('2024-10-31')
      AND DATE_ADD(data_fim, INTERVAL 42 DAY) >= DATE('2024-10-31')
  );

-- Resultado esperado: 0 puerperio_invalido
```

### Validação 5: Distribuição de IG

```sql
-- Gestações devem ter IG razoável
SELECT
    fase_atual,
    COUNT(*) AS total,
    MIN(ig_atual_semanas) AS ig_min,
    AVG(ig_atual_semanas) AS ig_media,
    MAX(ig_atual_semanas) AS ig_max,
    STDDEV(ig_atual_semanas) AS ig_desvio
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2024-10-31')
GROUP BY fase_atual;

-- Resultado esperado para Gestação:
-- ig_min: ~0-4 semanas
-- ig_media: ~18-22 semanas
-- ig_max: ~42 semanas

-- Resultado esperado para Puerpério:
-- ig_atual_semanas não é relevante (gestação já terminou)
-- ig_final_semanas deve estar entre 20-44 semanas
```

---

## 📊 Consultas Analíticas

### Evolução Temporal da Cobertura

```sql
SELECT
    data_snapshot,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(fase_atual = 'Puerpério') AS puerperios_ativos,
    COUNT(*) AS total_relevantes,
    ROUND(AVG(CASE WHEN fase_atual = 'Gestação' THEN ig_atual_semanas END), 1) AS ig_media_gestacoes
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### Distribuição por Trimestre (apenas Gestação)

```sql
SELECT
    data_snapshot,
    trimestre_atual_gestacao,
    COUNT(*) AS total_gestacoes
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE fase_atual = 'Gestação'
GROUP BY data_snapshot, trimestre_atual_gestacao
ORDER BY data_snapshot, trimestre_atual_gestacao;
```

### Desfechos por IG Final (apenas Puerpério)

```sql
SELECT
    tipo_desfecho,
    CASE
        WHEN ig_final_semanas < 22 THEN 'Aborto precoce'
        WHEN ig_final_semanas BETWEEN 22 AND 36 THEN 'Prematuro'
        WHEN ig_final_semanas BETWEEN 37 AND 41 THEN 'A termo'
        WHEN ig_final_semanas >= 42 THEN 'Pós-termo'
    END AS categoria_ig,
    COUNT(*) AS total
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2024-10-31')
  AND fase_atual = 'Puerpério'
  AND ig_final_semanas IS NOT NULL
GROUP BY tipo_desfecho, 2
ORDER BY tipo_desfecho, 2;
```

---

## ✅ Checklist de Implementação

- [ ] 1. **Backup V2**
  ```sql
  CREATE TABLE _gestacoes_historico_v2_backup AS
  SELECT * FROM _gestacoes_historico;
  ```

- [ ] 2. **Criar Procedimento V3**
  ```bash
  bq query --use_legacy_sql=false < "gestante_historico_V3_FINAL.sql"
  ```

- [ ] 3. **Testar com Data Única**
  ```sql
  CALL proced_1_gestacoes_historico(DATE('2024-10-31'));
  ```

- [ ] 4. **Validar com 5 Queries de Validação**

- [ ] 5. **Comparar Volume V2 vs V3**

- [ ] 6. **Validar Distribuição de Fases** (apenas Gestação e Puerpério)

- [ ] 7. **Atualizar Procedimentos Downstream** (2-6)

- [ ] 8. **Reprocessar Série Histórica Completa**

---

**Versão**: 3.0 FINAL
**Data**: 2024-12-02
**Status**: Implementação conforme especificação formal
**Regras**: Exatas conforme solicitado pelo usuário
