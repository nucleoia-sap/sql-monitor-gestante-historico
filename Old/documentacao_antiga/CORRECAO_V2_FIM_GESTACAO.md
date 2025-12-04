# Correção V2: Fim da Gestação Baseado em Eventos de Desfecho

## 🔴 Problema 2: CID "RESOLVIDO" ≠ Fim da Gestação

### Lógica Atual (INCORRETA)

```sql
finais AS (
    SELECT *
    FROM eventos_brutos
    WHERE
        tipo_evento = 'gestacao'
        AND situacao_cid = 'RESOLVIDO'  -- ❌ ERRADO!
)

gestacoes_unicas AS (
    SELECT
        data_inicio,
        (
            SELECT MIN(f.data_evento)
            FROM finais f
            WHERE f.data_evento > data_inicio
        ) AS data_fim  -- ❌ Primeiro CID marcado como RESOLVIDO
)
```

### Por que é Conceitualmente Errado?

#### 1. Status Administrativo vs. Evento Clínico

**"RESOLVIDO" é decisão do profissional, não evento real:**

| Situação | CID Status | Realidade Clínica |
|----------|------------|-------------------|
| Gestante em T1 com consulta de rotina | Z34.0 marcado "RESOLVIDO" | ❌ Gestação continua |
| Parto normal realizado | Pode estar "ATIVO" ainda | ✅ Gestação terminou |
| Aborto espontâneo | Z34 pode ficar "ATIVO" | ✅ Gestação terminou |

**Exemplo Real**:
- **2024-03-15**: CID Z34.0 (supervisão gravidez normal) marcado ATIVO
- **2024-04-20**: Médico marca Z34.0 como RESOLVIDO (gestante mudou de unidade)
- **2024-11-28**: Parto normal (CID O80.0)

**Com lógica atual**: `data_fim = 2024-04-20` ❌ (35 dias de gestação - impossível!)
**Correto**: `data_fim = 2024-11-28` ✅ (parto real)

#### 2. Múltiplos CIDs de Gestação

Gestante pode ter vários CIDs durante a gravidez:
- Z34.0 → Z34.8 → Z35.0 (evolução para alto risco)

**Problema**: Qual "RESOLVIDO" usar como fim?

#### 3. Inconsistência com Análise Temporal

```sql
-- Data referência: 2024-06-15
-- Gestação iniciada: 2024-03-01
-- CID marcado RESOLVIDO: 2024-04-01 (erro administrativo)
-- Parto real: 2024-11-20

-- Lógica atual:
fase_atual = 'Encerrada'  -- ❌ Errado! Está em T2, ~15 semanas

-- Correto:
fase_atual = 'Gestação'   -- ✅ Está em curso na data_referencia
```

---

## ✅ Solução: Eventos de Desfecho Obstétrico

### Princípio Conceitual

> **O fim da gestação ocorre quando há um EVENTO OBSTÉTRICO de desfecho, não quando um profissional altera status administrativo de um CID.**

### CIDs de Desfecho (Capítulo O: CID-10)

| Faixa | Descrição | Tipo Desfecho |
|-------|-----------|---------------|
| O00-O08 | Gravidez que termina em aborto | `aborto` |
| O80-O84 | Parto/Nascimento | `parto` |
| O85-O92 | Complicações puerpério | `puerperio_confirmado` |
| O10-O16 | Distúrbios hipertensivos | `outro_desfecho` |
| O60-O75 | Complicações trabalho de parto | `outro_desfecho` |

### Implementação

```sql
-- ✅ NOVO: Busca eventos reais de desfecho
eventos_desfecho AS (
    SELECT
        id_paciente,
        SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) AS data_desfecho,
        c.id AS cid_desfecho,
        CASE
            WHEN c.id BETWEEN 'O00' AND 'O08' THEN 'aborto'
            WHEN c.id BETWEEN 'O80' AND 'O84' THEN 'parto'
            WHEN c.id BETWEEN 'O85' AND 'O92' THEN 'puerperio_confirmado'
            ELSE 'outro_desfecho'
        END AS tipo_desfecho
    FROM episodio_assistencial
    WHERE c.id BETWEEN 'O00' AND 'O99'  -- CIDs obstétricos
)

-- ✅ NOVO: Associa gestação ao primeiro desfecho após início
gestacoes_unicas AS (
    SELECT
        data_inicio,
        (
            SELECT MIN(d.data_desfecho)
            FROM eventos_desfecho d
            WHERE d.id_paciente = i.id_paciente
              AND d.data_desfecho > i.data_evento
              AND DATE_DIFF(d.data_desfecho, i.data_evento, DAY) <= 320
        ) AS data_fim,
        (
            SELECT d.tipo_desfecho
            FROM eventos_desfecho d
            WHERE d.id_paciente = i.id_paciente
              AND d.data_desfecho > i.data_evento
              AND DATE_DIFF(d.data_desfecho, i.data_evento, DAY) <= 320
            ORDER BY d.data_desfecho
            LIMIT 1
        ) AS tipo_desfecho
    FROM inicios_deduplicados i
)
```

### Validação da Janela Temporal

**Por que 320 dias?**
- Gestação máxima biologicamente viável: ~300 dias
- Margem para registro atrasado: +20 dias
- **Total**: 320 dias

Isso evita associar partos de gestações diferentes:

```
Gestação 1: 2024-01-15 → 2024-10-10 (parto)
Gestação 2: 2025-03-20 → ?

❌ Sem limite: Parto de 10/2024 poderia ser associado a gestação de 03/2025
✅ Com limite: Apenas eventos dentro de 320 dias do início são considerados
```

---

## 📊 Impacto nas Análises

### Antes (CID RESOLVIDO)

```sql
SELECT
    COUNT(*) AS total_gestacoes,
    AVG(DATE_DIFF(data_fim, data_inicio, DAY)) AS duracao_media
FROM gestacoes_historico
WHERE data_fim IS NOT NULL;

-- Resultado INVÁLIDO:
-- total_gestacoes: 150,000
-- duracao_media: 87 dias ⚠️ (impossível! < 13 semanas)
```

**Por quê?** Muitos CIDs marcados RESOLVIDO precocemente (mudança de unidade, erro administrativo, etc.)

### Depois (Eventos de Desfecho)

```sql
SELECT
    COUNT(*) AS total_gestacoes,
    AVG(DATE_DIFF(data_fim, data_inicio, DAY)) AS duracao_media,
    tipo_desfecho,
    COUNT(*) AS total_por_tipo
FROM gestacoes_historico
WHERE data_fim IS NOT NULL
GROUP BY tipo_desfecho;

-- Resultado VÁLIDO:
-- total_gestacoes: 95,000 (apenas com desfecho real)
-- duracao_media: 268 dias ✅ (~38 semanas - razoável)
--
-- tipo_desfecho         | total_por_tipo
-- ----------------------|---------------
-- parto                 | 82,000
-- aborto                | 11,000
-- puerperio_confirmado  | 2,000
```

---

## 🆕 Novas Colunas Adicionadas

### Schema Atualizado

```sql
CREATE TABLE gestacoes_historico (
    -- Colunas existentes...
    data_inicio DATE,
    data_fim DATE,           -- ✅ Agora baseado em evento de desfecho
    data_fim_efetiva DATE,

    -- ✅ NOVAS COLUNAS
    tipo_desfecho STRING,    -- 'parto', 'aborto', 'puerperio_confirmado', 'outro_desfecho'
    cid_desfecho STRING,     -- CID do evento de desfecho (ex: 'O80.0')
    ig_atual_semanas INT64,  -- IG em semanas na data_snapshot
    ig_final_semanas INT64,  -- IG em semanas no desfecho (se houver)

    -- Demais colunas...
)
```

### Uso das Novas Colunas

```sql
-- Análise de desfechos por IG
SELECT
    CASE
        WHEN ig_final_semanas < 22 THEN 'Aborto precoce'
        WHEN ig_final_semanas BETWEEN 22 AND 36 THEN 'Parto prematuro'
        WHEN ig_final_semanas BETWEEN 37 AND 41 THEN 'Parto a termo'
        WHEN ig_final_semanas >= 42 THEN 'Parto pós-termo'
    END AS categoria_ig,
    tipo_desfecho,
    COUNT(*) AS total
FROM gestacoes_historico
WHERE data_fim IS NOT NULL
GROUP BY 1, 2;

-- Gestações em curso por IG atual
SELECT
    CASE
        WHEN ig_atual_semanas <= 13 THEN '1º trimestre'
        WHEN ig_atual_semanas BETWEEN 14 AND 27 THEN '2º trimestre'
        WHEN ig_atual_semanas >= 28 THEN '3º trimestre'
    END AS trimestre,
    COUNT(*) AS total_gestacoes
FROM gestacoes_historico
WHERE data_snapshot = DATE('2024-10-31')
  AND fase_atual = 'Gestação'
GROUP BY 1;
```

---

## 🧪 Validações da Correção

### Teste 1: IG Final Razoável

```sql
-- Todas as gestações com desfecho devem ter IG entre 1-45 semanas
SELECT
    COUNT(*) AS gestacoes_invalidas,
    MIN(ig_final_semanas) AS ig_min,
    MAX(ig_final_semanas) AS ig_max
FROM gestacoes_historico
WHERE data_fim IS NOT NULL
  AND (ig_final_semanas < 1 OR ig_final_semanas > 45);

-- Resultado esperado: 0 gestacoes_invalidas
```

### Teste 2: Distribuição de Desfechos

```sql
SELECT
    tipo_desfecho,
    COUNT(*) AS total,
    ROUND(AVG(ig_final_semanas), 1) AS ig_media,
    ROUND(STDDEV(ig_final_semanas), 1) AS ig_desvio
FROM gestacoes_historico
WHERE data_fim IS NOT NULL
  AND data_snapshot = DATE('2024-10-31')
GROUP BY tipo_desfecho;

-- Resultado esperado:
-- parto: IG média ~38-39 semanas
-- aborto: IG média ~8-12 semanas
```

### Teste 3: Comparação Antes/Depois

```sql
-- Versão ANTIGA (backup)
SELECT
    'ANTIGA (CID RESOLVIDO)' AS versao,
    COUNT(*) AS total_com_fim,
    ROUND(AVG(DATE_DIFF(data_fim, data_inicio, DAY)), 1) AS duracao_media_dias,
    MIN(DATE_DIFF(data_fim, data_inicio, DAY)) AS duracao_min,
    MAX(DATE_DIFF(data_fim, data_inicio, DAY)) AS duracao_max
FROM gestacoes_historico_backup
WHERE data_fim IS NOT NULL

UNION ALL

-- Versão NOVA (eventos de desfecho)
SELECT
    'NOVA (EVENTOS DESFECHO)' AS versao,
    COUNT(*) AS total_com_fim,
    ROUND(AVG(DATE_DIFF(data_fim, data_inicio, DAY)), 1) AS duracao_media_dias,
    MIN(DATE_DIFF(data_fim, data_inicio, DAY)) AS duracao_min,
    MAX(DATE_DIFF(data_fim, data_inicio, DAY)) AS duracao_max
FROM gestacoes_historico
WHERE data_fim IS NOT NULL;

-- Resultado esperado:
-- ANTIGA: duracao_media ~80-120 dias (inválido)
-- NOVA: duracao_media ~250-280 dias (válido)
```

---

## ⚠️ Casos Especiais

### Caso 1: Gestação sem Evento de Desfecho

**Situação**: Gestante faz pré-natal mas parto não é registrado no sistema (parto em outra rede, domiciliar, etc.)

**Como trata**:
```sql
-- data_fim = NULL
-- data_fim_efetiva = data_inicio + 299 dias (se data_referencia > data_inicio + 299)
-- fase_atual = 'Encerrada' (auto-encerramento após 299 dias)
```

### Caso 2: Aborto Espontâneo sem CID O00-O08

**Situação**: Aborto registrado apenas como "Z34 RESOLVIDO" sem CID específico

**Como trata**:
```sql
-- data_fim = NULL (não há evento de desfecho)
-- Pode ser detectado indiretamente:
--   - Última consulta em T1 (< 13 semanas)
--   - Longo período sem atendimentos
--   - Nova gestação iniciada depois
```

**Solução possível**: Adicionar heurística secundária (futuro enhancement)

### Caso 3: Parto + Puerpério com Múltiplos CIDs

**Situação**:
- 2024-10-20: O80.0 (parto normal)
- 2024-10-25: O85.0 (infecção puerperal)
- 2024-11-10: O90.0 (complicação puerpério)

**Como trata**:
```sql
-- data_fim = 2024-10-20 (primeiro evento de desfecho)
-- tipo_desfecho = 'parto'
-- cid_desfecho = 'O80.0'
-- Demais CIDs O85/O90 não alteram data_fim (já encerrou)
```

---

## 📋 Checklist de Implementação V2

- [ ] 1. **Backup completo**
  ```sql
  CREATE TABLE gestacoes_historico_v1_backup AS
  SELECT * FROM _gestacoes_historico;
  ```

- [ ] 2. **Atualizar schema** (adicionar colunas novas)
  ```sql
  ALTER TABLE _gestacoes_historico
  ADD COLUMN tipo_desfecho STRING,
  ADD COLUMN cid_desfecho STRING,
  ADD COLUMN ig_atual_semanas INT64,
  ADD COLUMN ig_final_semanas INT64;
  ```

- [ ] 3. **Criar procedimento V2**
  ```bash
  bq query --use_legacy_sql=false < "gestante_historico_V2_CORRIGIDO.sql"
  ```

- [ ] 4. **Teste com data única**
  ```sql
  CALL proced_1_gestacoes_historico(DATE('2024-10-31'));
  ```

- [ ] 5. **Validar com testes 1, 2 e 3**

- [ ] 6. **Comparar volumes e qualidade**

- [ ] 7. **Atualizar procedimentos downstream** (verificar compatibilidade)

- [ ] 8. **Reprocessar série histórica**

---

## 🎯 Benefícios da V2

### Qualidade de Dados

✅ **IG final válido**: ~38 semanas (não mais ~12 semanas)
✅ **Tipo de desfecho**: Saber se foi parto, aborto, etc.
✅ **Análise por IG**: Parto prematuro, a termo, pós-termo
✅ **Rastreabilidade**: CID específico do desfecho

### Análises Possíveis

- Taxa de parto prematuro (< 37 semanas)
- Taxa de aborto por IG
- Distribuição de IG no parto
- Adequação pré-natal por desfecho
- Fatores de risco para parto prematuro

### Consistência Conceitual

- Fim da gestação = evento clínico real
- Não depende de decisões administrativas
- Alinhado com definições obstétricas
- Histórico temporalmente coerente

---

**Versão**: 2.0
**Data**: 2024-12-02
**Status**: Proposta de correção
**Dependências**: Correção V1 (filtro temporal) aplicada
