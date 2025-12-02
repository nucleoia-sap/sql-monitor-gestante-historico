# Guia de Execução em Lote - Pipeline Histórico Pré-Natal

## 📋 Visão Geral

Este guia descreve como usar o script `executar_pipeline_datas_customizadas.sql` para processar múltiplas datas de uma vez, materializando apenas a tabela final `linha_tempo_historico_acumulado`.

---

## 🎯 Objetivo

Executar o pipeline completo (procedimentos 1-6) para uma lista específica de datas fornecida pelo usuário, acumulando apenas os resultados da tabela 6 (linha do tempo) em uma tabela permanente.

### Por que apenas tabela 6?

- **Economia de espaço**: Tabelas 1-5 são intermediárias e podem ser recriadas a qualquer momento
- **Análise temporal**: Tabela 6 contém todos os indicadores agregados necessários para análises históricas
- **Performance**: Reduz significativamente o espaço de armazenamento necessário

---

## 🚀 Como Usar

### Passo 1: Editar Lista de Datas

Abra o arquivo `executar_pipeline_datas_customizadas.sql` e localize a seção **CONFIGURAÇÃO USUÁRIO**:

```sql
-- Lista de datas para processar (formato: 'YYYY-MM-DD')
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-01-31'),
    DATE('2024-02-29'),
    DATE('2024-03-31'),
    -- Adicione suas datas aqui
];
```

#### Exemplos de Configuração

**Exemplo 1: Últimos dias de cada mês de 2024**
```sql
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-01-31'),
    DATE('2024-02-29'),
    DATE('2024-03-31'),
    DATE('2024-04-30'),
    DATE('2024-05-31'),
    DATE('2024-06-30'),
    DATE('2024-07-31'),
    DATE('2024-08-31'),
    DATE('2024-09-30'),
    DATE('2024-10-31'),
    DATE('2024-11-30'),
    DATE('2024-12-31')
];
```

**Exemplo 2: Datas específicas trimestrais**
```sql
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-03-31'),  -- Fim Q1
    DATE('2024-06-30'),  -- Fim Q2
    DATE('2024-09-30'),  -- Fim Q3
    DATE('2024-12-31')   -- Fim Q4
];
```

**Exemplo 3: Uma única data para teste**
```sql
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-10-31')
];
```

### Passo 2: Executar no BigQuery

1. Abra o BigQuery Console
2. Copie TODO o conteúdo do arquivo `executar_pipeline_datas_customizadas.sql`
3. Cole no editor de queries
4. Clique em **Run** ou pressione `Ctrl+Enter`
5. Aguarde a conclusão (pode levar vários minutos dependendo do número de datas)

### Passo 3: Monitorar Progresso

O script exibe logs detalhados durante a execução:

```
========================================
ETAPA 1: Criando/Verificando Tabela Acumulativa
========================================
✅ Tabela acumulativa criada/verificada com sucesso

========================================
ETAPA 2: Processando Datas Individualmente
Total de datas a processar: 12
========================================

----------------------------------------
📅 Processando data 1 de 12: 2024-01-31
----------------------------------------
  ⏳ [1/6] Executando proced_1_gestacoes_historico...
  ✅ [1/6] Procedimento 1 concluído
  ⏳ [2/6] Executando proced_2_atd_prenatal_aps_historico...
  ✅ [2/6] Procedimento 2 concluído
  ...
  ✅ Data 2024-01-31 processada com sucesso!
```

---

## 📊 Estrutura do Script

### Etapa 1: Criação da Tabela Acumulativa

O script cria automaticamente (se não existir) a tabela `linha_tempo_historico_acumulado` com:

- **Particionamento**: Por `data_snapshot` (obrigatório usar filtro de data nas queries)
- **Clustering**: Por `id_paciente` e `fase_atual` (otimiza queries por paciente/fase)
- **Schema completo**: Todos os campos da linha do tempo histórica

### Etapa 2: Processamento de Cada Data

Para cada data na lista:

1. **Executa procedimentos 1-6 sequencialmente**
   - Procedimento 1: Gestações
   - Procedimento 2: Atendimentos Pré-Natal
   - Procedimento 3: Visitas ACS
   - Procedimento 4: Consultas Emergenciais
   - Procedimento 5: Encaminhamentos SISREG
   - Procedimento 6: Linha do Tempo (agregação)

2. **Materializa apenas tabela 6**
   - INSERT na tabela acumulativa
   - Conta registros inseridos
   - Log de confirmação

3. **Tratamento de erros**
   - Se um procedimento falhar, pula para próxima data
   - Log detalhado do erro
   - Continua processamento das demais datas

### Etapa 3: Relatório Final

Ao final, exibe:

- Total de datas processadas
- Total de registros acumulados
- Resumo por data (gestações ativas, hipertensão, diabetes, etc.)
- Estatísticas gerais da tabela acumulativa

---

## ⏱️ Estimativa de Tempo

| Número de Datas | Tempo Estimado |
|-----------------|----------------|
| 1 data | 5-10 minutos |
| 4 datas (trimestral) | 20-40 minutos |
| 12 datas (mensal) | 1-2 horas |
| 24 datas (quinzenal) | 2-4 horas |

**Fatores que afetam performance**:
- Volume de dados nas tabelas fonte
- Horário de execução (off-peak é mais rápido)
- Capacidade de slots disponíveis no projeto BigQuery

---

## 🔍 Validação Pós-Execução

### Query 1: Verificar Snapshots Criados

```sql
SELECT
    data_snapshot,
    COUNT(*) AS total_gestacoes,
    COUNT(DISTINCT id_paciente) AS total_pacientes
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### Query 2: Comparar Evolução Temporal

```sql
SELECT
    data_snapshot,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(total_consultas_prenatal >= 6) AS adequacao_6_consultas,
    ROUND(100.0 * COUNTIF(total_consultas_prenatal >= 6) / NULLIF(COUNTIF(fase_atual = 'Gestação'), 0), 2) AS perc_adequacao
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### Query 3: Verificar Integridade

```sql
-- Verificar se há duplicatas
SELECT
    data_snapshot,
    id_gestacao,
    COUNT(*) AS vezes_aparece
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
GROUP BY data_snapshot, id_gestacao
HAVING COUNT(*) > 1;

-- Resultado esperado: 0 linhas (sem duplicatas)
```

---

## ⚠️ Troubleshooting

### Problema: "Procedure not found"

**Causa**: Um ou mais procedimentos não foram criados no BigQuery.

**Solução**:
```bash
# Criar todos os procedimentos primeiro
bq query --use_legacy_sql=false < "gestante_historico.sql"
bq query --use_legacy_sql=false < "2_atd_prenatal_aps_historico.sql"
bq query --use_legacy_sql=false < "3_visitas_acs_gestacao_historico.sql"
bq query --use_legacy_sql=false < "4_consultas_emergenciais_historico.sql"
bq query --use_legacy_sql=false < "5_encaminhamentos_historico.sql"
bq query --use_legacy_sql=false < "6_linha_tempo_historico.sql"
```

### Problema: Script interrompido no meio

**Causa**: Timeout do BigQuery ou perda de conexão.

**Solução**: O script tem tratamento de erros. Você pode:
1. Verificar quais datas foram processadas:
```sql
SELECT DISTINCT data_snapshot
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
ORDER BY data_snapshot;
```

2. Editar o array `datas_processar` removendo datas já processadas
3. Re-executar o script apenas com datas pendentes

### Problema: Erro "Partition filter required"

**Causa**: Query na tabela acumulativa sem filtro de `data_snapshot`.

**Solução**: Sempre incluir WHERE com data_snapshot:
```sql
-- ❌ ERRADO
SELECT * FROM linha_tempo_historico_acumulado;

-- ✅ CORRETO
SELECT * FROM linha_tempo_historico_acumulado
WHERE data_snapshot = DATE('2024-10-31');

-- ✅ CORRETO - múltiplas datas
SELECT * FROM linha_tempo_historico_acumulado
WHERE data_snapshot BETWEEN DATE('2024-01-31') AND DATE('2024-12-31');
```

### Problema: Registros duplicados

**Causa**: Script executado duas vezes para mesma data sem limpeza.

**Solução**: Limpar duplicatas antes de nova execução:
```sql
-- Deletar dados de data específica antes de reprocessar
DELETE FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
WHERE data_snapshot = DATE('2024-10-31');
```

---

## 🎯 Casos de Uso

### Caso 1: Build Histórico Inicial

**Objetivo**: Criar série histórica completa de 2024

```sql
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-01-31'), DATE('2024-02-29'), DATE('2024-03-31'),
    DATE('2024-04-30'), DATE('2024-05-31'), DATE('2024-06-30'),
    DATE('2024-07-31'), DATE('2024-08-31'), DATE('2024-09-30'),
    DATE('2024-10-31'), DATE('2024-11-30'), DATE('2024-12-31')
];
```

### Caso 2: Atualização Mensal

**Objetivo**: Adicionar snapshot do mês atual

```sql
-- Executar todo final de mês
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    LAST_DAY(CURRENT_DATE())
];
```

### Caso 3: Reprocessamento de Dados

**Objetivo**: Reprocessar trimestre específico

```sql
-- Primeiro: Limpar dados existentes
DELETE FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
WHERE data_snapshot IN (DATE('2024-07-31'), DATE('2024-08-31'), DATE('2024-09-30'));

-- Depois: Processar novamente
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-07-31'),
    DATE('2024-08-31'),
    DATE('2024-09-30')
];
```

### Caso 4: Análise Comparativa

**Objetivo**: Mesmo dia em meses diferentes

```sql
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-01-15'),
    DATE('2024-02-15'),
    DATE('2024-03-15'),
    DATE('2024-04-15'),
    DATE('2024-05-15'),
    DATE('2024-06-15')
];
```

---

## 📈 Análises Possíveis

Com a tabela acumulativa populada, você pode fazer análises como:

### Evolução da Cobertura de Pré-Natal

```sql
SELECT
    data_snapshot,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(total_consultas_prenatal >= 1) AS com_consulta,
    COUNTIF(total_consultas_prenatal >= 6) AS adequacao_6_consultas,
    ROUND(100.0 * COUNTIF(total_consultas_prenatal >= 6) / NULLIF(COUNTIF(fase_atual = 'Gestação'), 0), 2) AS perc_adequacao
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### Tendência de Condições Clínicas

```sql
SELECT
    data_snapshot,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(hipertensao_total = 1) AS com_hipertensao,
    COUNTIF(diabetes_total = 1) AS com_diabetes,
    ROUND(100.0 * COUNTIF(hipertensao_total = 1) / NULLIF(COUNTIF(fase_atual = 'Gestação'), 0), 2) AS prevalencia_has,
    ROUND(100.0 * COUNTIF(diabetes_total = 1) / NULLIF(COUNTIF(fase_atual = 'Gestação'), 0), 2) AS prevalencia_dm
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### Distribuição por Área Programática ao Longo do Tempo

```sql
SELECT
    data_snapshot,
    area_programatica,
    COUNT(*) AS total_gestacoes,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    ROUND(AVG(total_consultas_prenatal), 2) AS media_consultas
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
WHERE area_programatica IS NOT NULL
GROUP BY data_snapshot, area_programatica
ORDER BY data_snapshot, area_programatica;
```

---

## 💡 Boas Práticas

### 1. Teste com Data Única Primeiro

Antes de processar 12 meses, teste com uma data:

```sql
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-10-31')  -- Data de teste
];
```

### 2. Execute em Horários de Baixo Uso

Para grandes volumes, prefira:
- Madrugada (00:00 - 06:00)
- Finais de semana
- Evite horário comercial (09:00 - 18:00)

### 3. Monitore Custos

Verifique custos estimados antes de executar:
- BigQuery Console → Job History
- Observe "Bytes Processed" de execuções anteriores
- Calcule custo estimado (US$ 5 por TB processado)

### 4. Faça Backup Antes de Reprocessar

```sql
-- Criar backup antes de deletar/reprocessar
CREATE TABLE `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado_backup_20241028` AS
SELECT * FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`;
```

### 5. Documente Datas Processadas

Mantenha um registro de quando cada snapshot foi gerado:

```sql
-- Query para documentar
SELECT
    data_snapshot,
    COUNT(*) AS registros,
    CURRENT_TIMESTAMP() AS data_processamento
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

---

## 📚 Referências

- **Script Principal**: `executar_pipeline_datas_customizadas.sql`
- **Documentação Completa**: `README_HISTORICO_COMPLETO.md`
- **Guia de Testes**: `README_TESTES.md`
- **Relatório de Testes**: `RELATORIO_TESTES_PROCEDIMENTOS_3_A_6.md`
- **Exemplo Manual**: `construir_historico_completo.sql`

---

## 🆘 Suporte

Se encontrar problemas:

1. Verifique logs do script para identificar qual procedimento falhou
2. Consulte seção Troubleshooting deste guia
3. Revise `README_TESTES.md` para validações específicas
4. Verifique `RELATORIO_TESTES_PROCEDIMENTOS_3_A_6.md` para problemas conhecidos

---

**Última atualização**: 2025-10-28
**Versão**: 1.0
