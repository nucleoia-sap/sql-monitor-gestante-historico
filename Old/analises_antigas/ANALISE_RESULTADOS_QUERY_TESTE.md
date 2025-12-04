# 📊 Análise dos Resultados - query_teste_gestacoes.sql

**Data de Execução**: 2025-12-02
**Data de Referência**: 2025-01-01
**Janela Temporal**: 340 dias antes da data de referência (2024-02-26 a 2025-01-01)

---

## 🎯 Resumo Executivo

A query de teste `query_teste_gestacoes.sql` foi executada com sucesso no BigQuery, retornando dados de gestações e puerpérios ativos na data de referência.

### ⚠️ Problema Crítico Identificado: DUPLICAÇÕES MASSIVAS

**Achado Principal**: Múltiplas gestantes aparecem com **10 a 17 gestações simultâneas** com:
- **Mesma data de início** (data_inicio)
- **Mesmo desfecho e data de fim** (data_fim, tipo_desfecho, cid_desfecho)
- **Mesmo HCI base** (id_hci diferentes, mas todos relacionados à mesma gestação)
- **Dados clínicos idênticos** (IG, DPP, trimestre)

---

## 📋 Casos Problemáticos Analisados

### Caso 1: Alessa Oliveira da Costa (CPF: 20469417722)

| Métrica | Valor |
|---------|-------|
| **Gestações registradas** | **12 registros idênticos** (numero_gestacao 1 a 12) |
| Data início | 2024-02-10 (todas iguais) |
| Data fim | 2024-11-24 (todas iguais) |
| Tipo desfecho | Parto (O800) (todas iguais) |
| IG final | 42 semanas (todas iguais) |
| Fase atual | Puerpério (todas iguais) |
| IDs HCI | 12 diferentes (fc4c528a..., b3be37a7..., etc.) |

**Análise**: Mesma gestação aparece duplicada 12 vezes com IDs de episódios assistenciais diferentes.

---

### Caso 2: Lara Jane Pereira Silva (CPF: 17361746730)

| Métrica | Valor |
|---------|-------|
| **Gestações registradas** | **17 registros idênticos** (numero_gestacao 1 a 17) |
| Data início | 2024-02-15 (todas iguais) |
| Data fim | 2024-12-06 (todas iguais) |
| Tipo desfecho | Outro desfecho (O249) (todas iguais) |
| IG final | 42 semanas (todas iguais) |
| Fase atual | Puerpério (todas iguais) |
| IDs HCI | 17 diferentes |

**Análise**: **PIOR CASO** - 17 duplicações da mesma gestação.

---

### Caso 3: Suzane dos Santos Napolitano (CPF: 12535785757)

| Métrica | Valor |
|---------|-------|
| **Gestações registradas** | **10 registros idênticos** (numero_gestacao 1 a 10) |
| Data início | 2024-02-22 (todas iguais) |
| Data fim | 2024-11-27 (todas iguais) |
| Tipo desfecho | Outro desfecho (O244) (todas iguais) |
| IG final | 40 semanas (todas iguais) |

---

### Caso 4: Antonia Erileuda Rodrigues (CPF: 09606275701)

| Métrica | Valor |
|---------|-------|
| **Gestações registradas** | **2 registros idênticos** (numero_gestacao 1 e 2) |
| Data início | 2024-03-01 (ambas iguais) |
| Data fim | 2024-12-05 (ambas iguais) |
| Tipo desfecho | Outro desfecho (O100) (ambas iguais) |

---

## 🔍 Análise de Causa Raiz

### Hipótese Principal: Lógica de Agrupamento Falha

A query aplica a seguinte lógica para identificar gestações:

```sql
-- CTE: primeiro_desfecho
SELECT
    i.id_hci,  -- ⚠️ PROBLEMA: id_hci está DENTRO do GROUP BY
    i.id_paciente,
    i.data_evento AS data_inicio,
    MIN(d.data_desfecho) AS data_fim,
    -- ...
FROM eventos_brutos i
LEFT JOIN eventos_desfecho d
    ON i.id_paciente = d.id_paciente
    AND d.data_desfecho > i.data_evento
    AND DATE_DIFF(d.data_desfecho, i.data_evento, DAY) <= 320
GROUP BY i.id_hci, i.id_paciente, i.data_evento  -- ⚠️ id_hci não deveria estar aqui
```

**Problema**: `id_hci` (identificador do episódio assistencial) está no `GROUP BY`, fazendo com que:

1. **Cada episódio assistencial** com o CID de gestação (Z321, Z34%, Z35%) gera **um registro separado**
2. Se a gestante teve **múltiplas consultas/atendimentos** onde o CID foi registrado, ela terá **múltiplos id_hci**
3. Todos os id_hci com a **mesma data_inicio** são tratados como **gestações diferentes**
4. O `numero_gestacao` é calculado por `ROW_NUMBER() OVER (PARTITION BY id_paciente ORDER BY data_inicio)`, gerando sequências 1, 2, 3... para registros com **data_inicio idêntica**

### Cenário Real Ilustrado

**Paciente: Lara Jane (CPF: 17361746730)**

```
Consulta 1 (10/02): Registra CID Z321 → id_hci = "cb1604c0..."
Consulta 2 (15/02): Registra CID Z34  → id_hci = "bb32856a..."
Consulta 3 (20/02): Registra CID Z34  → id_hci = "0170203f..."
...
Consulta 17 (múltiplas datas): Registra CIDs gestacionais → 17 id_hci diferentes
```

**Resultado da Query**:
- Todos os 17 episódios têm `data_inicio = 2024-02-15` (data do primeiro CID ou agregação por janela de 60 dias)
- `GROUP BY i.id_hci` → 17 linhas separadas
- `ROW_NUMBER()` → numero_gestacao = 1, 2, 3, ..., 17
- **Interpretação incorreta**: 17 gestações diferentes da mesma paciente

---

## ✅ Solução Proposta

### Correção na CTE `primeiro_desfecho`

**Remover `id_hci` do GROUP BY** e agregar adequadamente:

```sql
-- VERSÃO CORRIGIDA
primeiro_desfecho AS (
    SELECT
        -- Selecionar apenas UM id_hci por gestação (primeiro ou qualquer)
        ARRAY_AGG(i.id_hci ORDER BY i.data_evento LIMIT 1)[OFFSET(0)] AS id_hci,
        i.id_paciente,
        i.data_evento AS data_inicio,
        MIN(d.data_desfecho) AS data_fim,
        ARRAY_AGG(d.tipo_desfecho ORDER BY d.data_desfecho LIMIT 1)[OFFSET(0)] AS tipo_desfecho,
        ARRAY_AGG(d.cid_desfecho ORDER BY d.data_desfecho LIMIT 1)[OFFSET(0)] AS cid_desfecho
    FROM eventos_brutos i
    LEFT JOIN eventos_desfecho d
        ON i.id_paciente = d.id_paciente
        AND d.data_desfecho > i.data_evento
        AND DATE_DIFF(d.data_desfecho, i.data_evento, DAY) <= 320
    WHERE i.data_evento <= data_referencia
        AND i.tipo_evento = 'gestacao'
    GROUP BY i.id_paciente, i.data_evento  -- ✅ APENAS id_paciente e data_inicio
)
```

### Lógica de Deduplicação Aprimorada

Se a intenção é manter múltiplos episódios por gestação (ex: para rastreabilidade), adicionar:

```sql
-- Após primeiro_desfecho, deduplica por janela de 60 dias
gestacoes_agrupadas AS (
    SELECT
        *,
        CASE
            WHEN LAG(data_inicio) OVER (
                PARTITION BY id_paciente
                ORDER BY data_inicio
            ) IS NULL THEN 1
            WHEN DATE_DIFF(
                data_inicio,
                LAG(data_inicio) OVER (
                    PARTITION BY id_paciente
                    ORDER BY data_inicio
                ),
                DAY
            ) >= 60 THEN 1  -- Nova gestação se > 60 dias
            ELSE 0
        END AS nova_gestacao_flag
    FROM primeiro_desfecho
),

gestacoes_numeradas AS (
    SELECT
        *,
        SUM(nova_gestacao_flag) OVER (
            PARTITION BY id_paciente
            ORDER BY data_inicio
        ) AS grupo_gestacao
    FROM gestacoes_agrupadas
),

gestacoes_deduplicadas AS (
    SELECT *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY id_paciente, grupo_gestacao
                ORDER BY data_inicio
            ) AS rn
        FROM gestacoes_numeradas
    )
    WHERE rn = 1  -- ✅ Apenas uma linha por grupo de gestação
)
```

---

## 📊 Impacto nos Indicadores

### Antes da Correção (Estado Atual)
- **Registro duplicado artificialmente** infla contagens
- **numero_gestacao** não reflete gestações reais
- **Indicadores de cobertura** serão incorretos (múltiplos registros da mesma gestação)
- **Análises temporais** comprometidas

### Após Correção Esperada
- **1 registro por gestação real**
- **numero_gestacao** sequencial correto
- **Indicadores precisos** de cobertura e acompanhamento
- **Análises confiáveis** para políticas públicas

---

## 🔧 Ações Recomendadas

### Prioridade ALTA 🔴

1. **Corrigir lógica de agrupamento**
   - Remover `id_hci` do `GROUP BY` em `primeiro_desfecho`
   - Implementar deduplicação por janela de 60 dias
   - Testar com os CPFs problemáticos identificados

2. **Validar resultados corrigidos**
   ```sql
   -- Verificar casos específicos após correção
   SELECT
       id_paciente,
       COUNT(*) AS gestacoes_registradas,
       STRING_AGG(DISTINCT CAST(data_inicio AS STRING), ', ') AS datas_inicio
   FROM resultado_corrigido
   WHERE id_paciente IN (
       'e44c77eb6c9826d69c28926cd38e6342',  -- Alessa (esperado: 1)
       '6266030c3866c80c6584d74289942f0e'   -- Lara (esperado: 1)
   )
   GROUP BY id_paciente;
   ```

3. **Atualizar procedures dependentes**
   - `proced_1_gestacoes_historico`: Aplicar mesma correção
   - Procedures 2-6: Validar integridade referencial após correção

### Prioridade MÉDIA 🟡

4. **Documentar lógica de negócio**
   - Especificar claramente: "1 gestação = múltiplos episódios assistenciais"
   - Definir critério de deduplicação (janela de 60 dias)
   - Adicionar comentários explicativos no código SQL

5. **Implementar checks de qualidade**
   ```sql
   -- Check automático: detectar duplicações suspeitas
   SELECT
       id_paciente,
       data_inicio,
       COUNT(*) AS ocorrencias
   FROM _gestacoes_historico
   WHERE data_snapshot = DATE('2025-01-01')
   GROUP BY id_paciente, data_inicio
   HAVING COUNT(*) > 1
   ORDER BY ocorrencias DESC;
   ```

---

## 📈 Estatísticas Preliminares (Com Duplicações)

⚠️ **Nota**: Estatísticas imprecisas devido às duplicações identificadas

### Amostra Analisada (100 primeiros registros)

| Métrica | Valor |
|---------|-------|
| Total de registros | 100 |
| Fase: Puerpério | 100 (100%) |
| Fase: Gestação | 0 (0%) |
| Pacientes únicos | ~5-10 (estimado) |
| Gestações reais estimadas | ~5-10 |
| **Fator de duplicação médio** | **~10-15x** |

### Distribuição de Desfechos

| Tipo Desfecho | Quantidade (com duplicação) |
|---------------|----------------------------|
| outro_desfecho | ~70% |
| parto (O800) | ~30% |
| aborto | 0 |
| puerperio_confirmado | 0 |

### Range Temporal

| Métrica | Valor |
|---------|-------|
| Data início mínima | 2024-02-10 |
| Data início máxima | 2024-03-01 |
| Range | ~19 dias |
| Data fim média | Novembro-Dezembro 2024 |
| IG final média | 40-42 semanas |

---

## 🎓 Lições Aprendidas

1. **GROUP BY com chaves granulares** (id_hci) cria duplicações quando a intenção é agrupar por entidade lógica (gestação)

2. **ROW_NUMBER() sem deduplicação adequada** gera sequências enganosas que parecem múltiplas ocorrências independentes

3. **Episódios assistenciais ≠ Gestações**: Um mesmo evento clínico (gestação) gera múltiplos registros administrativos (consultas)

4. **Validação manual crítica**: Análise de casos reais revelou problema que testes automatizados não captariam

5. **Documentação de negócio essencial**: Especificar claramente o que constitui "1 gestação" vs "múltiplos atendimentos da mesma gestação"

---

## 📚 Referências e Contexto

### Estrutura de Dados Original
- **Tabela fonte**: `rj-sms.saude_historico_clinico.episodio_assistencial`
- **Array aninhado**: `condicoes` (CIDs registrados por atendimento)
- **Granularidade**: 1 registro = 1 episódio assistencial (consulta/atendimento)

### Lógica de Negócio Esperada
- **Janela de agrupamento**: 60 dias entre CIDs para considerar mesma gestação
- **Auto-encerramento**: 299 dias após início se sem data_fim
- **Fase puerpério**: Até 42 dias após data_fim

### Procedures Dependentes
1. `proced_1_gestacoes_historico` ← **Requer correção prioritária**
2. `proced_2_atd_prenatal_aps_historico` ← Depende de gestações corretas
3. `proced_6_linha_tempo_historico` ← Agregações serão incorretas

---

## 🚀 Próximos Passos

1. ✅ **Problema identificado e documentado**
2. ✅ **Correção implementada na query de teste** (2025-12-02)
3. ✅ **Validação com casos reais executada** (Antonia: 2 → 1 gestações)
4. ✅ **Análise estatística adicionada** (2025-12-02)
5. ✅ **Correção de tipos UNION ALL** (2025-12-02)
6. ⏳ **Aplicar correção em `proced_1_gestacoes_historico`**
7. ⏳ **Re-executar pipeline completo**
8. ⏳ **Validar integridade dos 6 proced