# Correção Conceitual do Histórico de Gestações

## 🔴 Problema Identificado

A versão atual de `gestante_historico.sql` tem uma **inconsistência conceitual crítica** que compromete a validade dos snapshots históricos.

### Comportamento Atual (INCORRETO)

```sql
-- 1. Busca TODOS os eventos da história (sem filtro temporal)
eventos_brutos AS (
    SELECT ...
    FROM episodio_assistencial
    WHERE c.data_diagnostico IS NOT NULL
    -- ❌ SEM FILTRO: Traz eventos de 2020, 2021, 2022, 2023, 2024, 2025...
)

-- 2. Mas calcula fase_atual usando data_referencia
filtrado AS (
    SELECT
        CASE
            WHEN DATE_ADD(data_inicio, INTERVAL 299 DAY) > data_referencia
            THEN 'Gestação'
        END AS fase_atual
)
```

### Consequência

**Para `data_referencia = '2025-05-01'`:**
- ✅ Gestação iniciada em 2025-04-15 → **incluída** (correto)
- ❌ Gestação iniciada em 2020-03-10, encerrada em 2020-12-01 → **incluída** (ERRADO!)
- ❌ Gestação iniciada em 2023-06-20, encerrada em 2024-02-15 → **incluída** (ERRADO!)

**Resultado**: Snapshot inclui gestações que já estavam encerradas há anos, calculando `fase_atual = 'Encerrada'` para elas, mas sem sentido conceitual para aquele ponto no tempo.

---

## 🎯 Conceito Correto de Snapshot Histórico

### Definição: "Gestação Visível" em data_referencia

Uma gestação deve aparecer no snapshot de `data_referencia` **SE E SOMENTE SE**:

1. **Está em curso (Gestação)**:
   - `data_inicio ≤ data_referencia`
   - `data_fim IS NULL` OU `data_fim > data_referencia`
   - `data_inicio + 299 dias > data_referencia`

2. **Está no puerpério**:
   - `data_fim ≤ data_referencia`
   - `data_fim + 45 dias ≥ data_referencia`

3. **NÃO deve aparecer** se:
   - Gestação encerrou há mais de 45 dias antes de data_referencia
   - Gestação ainda não iniciou (data_inicio > data_referencia)

### Exemplo Prático

**Snapshot em 2025-05-01:**

| Gestação | data_inicio | data_fim | Status em 2025-05-01 | Incluir? |
|----------|-------------|----------|---------------------|----------|
| A | 2025-03-15 | NULL | Gestação (7 semanas) | ✅ SIM |
| B | 2024-12-20 | 2025-04-25 | Puerpério (6 dias) | ✅ SIM |
| C | 2024-08-10 | 2024-11-15 | Encerrada (167 dias) | ❌ NÃO |
| D | 2025-06-01 | NULL | Não iniciou | ❌ NÃO |
| E | 2023-05-20 | 2024-01-10 | Encerrada (477 dias) | ❌ NÃO |

---

## ✅ Solução Implementada

### Mudança 1: Filtro Temporal em eventos_brutos

```sql
eventos_brutos AS (
    SELECT ...
    FROM episodio_assistencial
    WHERE
        -- Filtros existentes...
        -- ✅ NOVO: Janela temporal relevante
        AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) <= data_referencia
        AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) >= DATE_SUB(data_referencia, INTERVAL 310 DAY)
)
```

**Justificativa da janela de 310 dias**:
- Gestação máxima: 299 dias
- Puerpério: 45 dias
- Total: 344 dias
- **Margem conservadora**: 310 dias para cobrir gestações em curso + puerpério

### Mudança 2: Filtro de Visibilidade em filtrado

```sql
filtrado AS (
    SELECT
        gcs.*,
        CASE
            WHEN gcs.data_fim IS NULL
            AND DATE_ADD(gcs.data_inicio, INTERVAL 299 DAY) > data_referencia
            THEN 'Gestação'

            WHEN gcs.data_fim IS NOT NULL
            AND DATE_DIFF(data_referencia, gcs.data_fim, DAY) <= 45
            THEN 'Puerpério'

            ELSE 'Encerrada'
        END AS fase_atual,
        ...
    FROM gestacoes_com_status gcs
    -- ✅ NOVO: Filtra para incluir apenas gestações "visíveis"
    WHERE
        -- Inclui Gestação (em curso na data_referencia)
        (
            gcs.data_fim IS NULL
            AND DATE_ADD(gcs.data_inicio, INTERVAL 299 DAY) > data_referencia
        )
        OR
        -- Inclui Puerpério (fim recente, dentro de 45 dias)
        (
            gcs.data_fim IS NOT NULL
            AND DATE_DIFF(data_referencia, gcs.data_fim, DAY) <= 45
        )
)
```

**Resultado**: Apenas gestações conceitualmente relevantes na `data_referencia` são incluídas no snapshot.

---

## 📊 Impacto Esperado

### Antes da Correção

**Snapshot 2025-05-01:**
- Total: 250,000 gestações
- Fase Gestação: 45,000
- Fase Puerpério: 8,000
- Fase Encerrada: **197,000** ⚠️ (gestações de anos anteriores!)

### Depois da Correção

**Snapshot 2025-05-01:**
- Total: **53,000** gestações (redução de ~80%)
- Fase Gestação: 45,000
- Fase Puerpério: 8,000
- Fase Encerrada: **0** ✅ (removidas, pois não são relevantes nesta data)

---

## 🧪 Validação da Correção

### Query de Teste 1: Verificar Janela Temporal

```sql
-- Após executar procedimento corrigido
SELECT
    MIN(data_inicio) AS data_inicio_min,
    MAX(data_inicio) AS data_inicio_max,
    DATE_DIFF(DATE('2025-05-01'), MIN(data_inicio), DAY) AS dias_min,
    DATE_DIFF(DATE('2025-05-01'), MAX(data_inicio), DAY) AS dias_max
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2025-05-01');

-- Resultado esperado:
-- dias_min ≤ 310 (pode ter gestações antigas ainda em puerpério)
-- dias_max ≥ 0 (gestações recentes)
```

### Query de Teste 2: Verificar Fase Encerrada

```sql
-- Não deve haver gestações com fase_atual = 'Encerrada'
SELECT
    fase_atual,
    COUNT(*) AS total
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2025-05-01')
GROUP BY fase_atual;

-- Resultado esperado:
-- Gestação: N
-- Puerpério: M
-- Encerrada: 0 ✅ (não deve aparecer)
```

### Query de Teste 3: Validar Lógica de Fase

```sql
-- Todas as gestações devem satisfazer a condição de visibilidade
SELECT
    COUNT(*) AS gestacoes_invalidas
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2025-05-01')
AND NOT (
    -- Condição 1: Gestação em curso
    (
        data_fim IS NULL
        AND DATE_ADD(data_inicio, INTERVAL 299 DAY) > DATE('2025-05-01')
    )
    OR
    -- Condição 2: Puerpério recente
    (
        data_fim IS NOT NULL
        AND DATE_DIFF(DATE('2025-05-01'), data_fim, DAY) <= 45
    )
);

-- Resultado esperado: 0 (zero gestações inválidas)
```

---

## 📝 Checklist de Implementação

- [ ] 1. **Backup**: Criar backup da tabela atual
  ```sql
  CREATE TABLE `rj-sms-sandbox.sub_pav_us._gestacoes_historico_backup` AS
  SELECT * FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`;
  ```

- [ ] 2. **Atualizar Procedimento**: Executar script corrigido
  ```bash
  bq query --use_legacy_sql=false < "gestante_historico_CORRIGIDO.sql"
  ```

- [ ] 3. **Teste com 1 Data**: Executar para data_referencia de teste
  ```sql
  CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-10-31'));
  ```

- [ ] 4. **Validar Resultados**: Executar queries de teste 1, 2 e 3

- [ ] 5. **Comparar Volumes**:
  ```sql
  -- Antiga
  SELECT COUNT(*) FROM _gestacoes_historico_backup WHERE data_snapshot = DATE('2024-10-31');
  -- Nova
  SELECT COUNT(*) FROM _gestacoes_historico WHERE data_snapshot = DATE('2024-10-31');
  ```

- [ ] 6. **Atualizar Procedimentos Dependentes**: Procedimentos 2-6 dependem da tabela `_gestacoes_historico`, verificar se continuam funcionando

- [ ] 7. **Reprocessar Datas Históricas**: Re-executar pipeline para datas já processadas

---

## ⚠️ Impactos em Procedimentos Downstream

### Procedimento 2: atd_prenatal_aps_historico
**Impacto**: ✅ **Benefício direto**
- Menos JOINs desnecessários com gestações antigas
- Performance melhorada
- **Ação**: Nenhuma mudança necessária

### Procedimento 3: visitas_acs_gestacao_historico
**Impacto**: ✅ **Benefício direto**
- Redução de volume de dados processados
- **Ação**: Nenhuma mudança necessária

### Procedimento 4: consultas_emergenciais_historico
**Impacto**: ✅ **Benefício direto**
- **Ação**: Nenhuma mudança necessária

### Procedimento 5: encaminhamentos_historico
**Impacto**: ⚠️ **Precisa revisão**
- Este procedimento reconstrói gestações internamente (não usa `_gestacoes_historico`)
- **Ação**: Aplicar mesma correção de filtro temporal

### Procedimento 6: linha_tempo_historico
**Impacto**: ✅ **Benefício direto**
- Agregações mais consistentes
- **Ação**: Nenhuma mudança necessária

---

## 🎓 Conceitos de Snapshot Temporal

### Princípio Fundamental
> **Um snapshot histórico deve representar a realidade observável naquela data.**

### Analogia
Imagine que você tem uma foto da sala de espera de uma clínica tirada em 2025-05-01 às 14h:

- ✅ **Aparece na foto**: Gestantes que estavam lá naquele momento
- ❌ **Não aparece**: Gestantes que foram atendidas em 2023 (não estão mais lá)
- ❌ **Não aparece**: Gestantes que chegarão em junho/2025 (ainda não chegaram)

### Aplicação ao Código
```sql
-- ❌ ERRADO: "Foto" que inclui pessoas que não estavam lá
SELECT * FROM gestacoes -- Todas as gestações de sempre

-- ✅ CORRETO: "Foto" do que realmente existia naquela data
SELECT * FROM gestacoes
WHERE (em_curso_em(data_referencia) OR puerperio_em(data_referencia))
```

---

## 📚 Referências

- **Tempo gestacional**: 280 dias (40 semanas) desde DUM
- **Auto-encerramento**: 299 dias (42 semanas + 5 dias)
- **Puerpério**: 45 dias pós-parto (6 semanas + 3 dias)
- **Janela total**: 299 + 45 = 344 dias

### Documentação Relacionada
- `README_HISTORICO_COMPLETO.md`: Documentação geral do sistema
- `README_GESTACOES_HISTORICO.md`: Lógica de identificação de gestações
- `CLAUDE.md`: Guia para desenvolvimento

---

**Versão**: 1.0
**Data**: 2024-12-02
**Status**: Proposta de correção
