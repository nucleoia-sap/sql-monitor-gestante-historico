# Quick Start - Pipeline Histórico Pré-Natal

Guia rápido para começar a usar o sistema em **5 minutos**.

---

## 🚀 Início Rápido (3 Passos)

### Passo 1: Criar Procedimentos (uma vez apenas)

Execute cada arquivo SQL no BigQuery Console para criar os 6 procedimentos:

```bash
# Via BigQuery CLI (se disponível)
bq query --use_legacy_sql=false < "gestante_historico.sql"
bq query --use_legacy_sql=false < "2_atd_prenatal_aps_historico.sql"
bq query --use_legacy_sql=false < "3_visitas_acs_gestacao_historico.sql"
bq query --use_legacy_sql=false < "4_consultas_emergenciais_historico.sql"
bq query --use_legacy_sql=false < "5_encaminhamentos_historico.sql"
bq query --use_legacy_sql=false < "6_linha_tempo_historico.sql"
```

**OU** copie e cole cada arquivo no BigQuery Console manualmente.

### Passo 2: Configurar Suas Datas

Edite o arquivo `executar_pipeline_datas_customizadas.sql` (linhas 15-28):

```sql
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-01-31'),
    DATE('2024-02-29'),
    DATE('2024-03-31')
    -- Adicione mais datas conforme necessário
];
```

### Passo 3: Executar

1. Copie TODO o conteúdo de `executar_pipeline_datas_customizadas.sql`
2. Cole no BigQuery Console
3. Clique em **Run**
4. Aguarde conclusão (5-60 minutos dependendo do número de datas)

**Pronto!** A tabela `linha_tempo_historico_acumulado` estará populada.

---

## 📊 Consultar Resultados

### Query Básica

```sql
SELECT
    data_snapshot,
    COUNT(*) AS total_gestacoes,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
WHERE data_snapshot = DATE('2024-10-31')
GROUP BY data_snapshot;
```

### Evolução Temporal

```sql
SELECT
    data_snapshot,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(total_consultas_prenatal >= 6) AS adequacao_6_consultas,
    ROUND(100.0 * COUNTIF(total_consultas_prenatal >= 6) /
          NULLIF(COUNTIF(fase_atual = 'Gestação'), 0), 2) AS perc_adequacao
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

---

## 🎯 Casos de Uso Comuns

### Caso 1: Teste Inicial (1 data)

```sql
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-10-31')
];
```

**Tempo estimado**: 5-10 minutos

### Caso 2: Histórico Mensal 2024 (12 datas)

```sql
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-01-31'), DATE('2024-02-29'), DATE('2024-03-31'),
    DATE('2024-04-30'), DATE('2024-05-31'), DATE('2024-06-30'),
    DATE('2024-07-31'), DATE('2024-08-31'), DATE('2024-09-30'),
    DATE('2024-10-31'), DATE('2024-11-30'), DATE('2024-12-31')
];
```

**Tempo estimado**: 1-2 horas

### Caso 3: Atualização Mensal

```sql
-- Adicionar apenas o mês atual
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    LAST_DAY(CURRENT_DATE())
];
```

**Tempo estimado**: 5-10 minutos

---

## ⚠️ Problemas Comuns

### "Procedure not found"
→ Execute Passo 1 primeiro (criar procedimentos)

### "Partition filter required"
→ Sempre use `WHERE data_snapshot = ...` nas queries

### Script parou no meio
→ Veja quais datas foram processadas e remova do array

---

## 📚 Próximos Passos

Após executar o Quick Start, consulte:

- **`GUIA_EXECUCAO_LOTE.md`**: Guia completo de uso
- **`README_HISTORICO_COMPLETO.md`**: Documentação detalhada
- **`RELATORIO_TESTES_PROCEDIMENTOS_3_A_6.md`**: Resultados de testes

---

## 💡 Dica

Sempre teste com **1 data** primeiro antes de processar múltiplas datas!

```sql
-- Teste primeiro com esta configuração:
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-10-31')  -- Apenas 1 data para teste
];
```

Se funcionar, aí sim configure múltiplas datas.

---

**Última atualização**: 2025-10-28
