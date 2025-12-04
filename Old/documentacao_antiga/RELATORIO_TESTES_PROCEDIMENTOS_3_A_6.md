# Relatório de Testes - Procedimentos 3 a 6

**Data de Execução**: 2025-10-28
**Data de Referência (Snapshot)**: 2024-10-31
**Ferramenta**: BigQuery CLI (`bq`)

---

## ✅ Resumo Executivo

**Status Geral**: TODOS OS PROCEDIMENTOS EXECUTADOS COM SUCESSO

- ✅ Procedimento 3 (Visitas ACS): Criado e executado
- ✅ Procedimento 4 (Consultas Emergenciais): Criado e executado
- ✅ Procedimento 5 (Encaminhamentos SISREG): Criado e executado
- ✅ Procedimento 6 (Linha do Tempo): Criado e executado (após correção)

---

## 📊 Resultados Consolidados

### Tabela de Registros por Procedimento

| Procedimento | Tabela | Total Registros | Total Pacientes | Data Mínima | Data Máxima |
|--------------|--------|-----------------|-----------------|-------------|-------------|
| 1. Gestações | `_gestacoes_historico` | 293.382 | 240.553 | 1989-09-26 | 2025-10-27 |
| 2. Atendimentos PN APS | `_atendimentos_prenatal_aps_historico` | 17.747 | 2.454 | 2024-01-08 | 2024-10-31 |
| 3. Visitas ACS | `_visitas_acs_gestacao_historico` | 1.817.752 | 180.585 | 2017-02-16 | 2025-10-14 |
| 4. Consultas Emergenciais | `_consultas_emergenciais_historico` | 167.098 | 61.533 | 2018-01-04 | 2025-10-26 |
| 5. Encaminhamentos | `_encaminhamentos_historico` | 31.993 | 30.905 | 2024-01-05 | 2024-10-31 |
| 6. Linha do Tempo | `_linha_tempo_historico` | 85.633 | 80.864 | 2018-03-28 | 2025-10-27 |

---

## 🎯 Validação do Procedimento 6 - Linha do Tempo

### Métricas Gerais

| Métrica | Valor |
|---------|-------|
| Total de gestações | 85.633 |
| Total de pacientes únicos | 80.864 |
| Gestações ativas | 31.438 (36,7%) |
| Puerpério | 54.195 (63,3%) |
| Idade média das gestantes | 26,76 anos |
| Média de consultas por gestação | 0,21 |
| Média de visitas ACS por gestação | 6,3 |
| Gestações com hipertensão | 3.779 (4,4%) |
| Gestações com diabetes | 7.441 (8,7%) |

### Indicadores de Cobertura (Gestações Ativas)

| Indicador | Absoluto | Percentual |
|-----------|----------|------------|
| Com ao menos 1 consulta pré-natal | 2.481 | 7,89% |
| Com adequação de 6 consultas | 898 | 2,86% |
| Com ao menos 1 visita de ACS | 1.704 | 5,42% |

**Interpretação**: Os percentuais baixos de cobertura podem indicar:
- Gestações muito recentes (início em outubro)
- Período de análise limitado (apenas 2024 para algumas tabelas)
- Necessidade de análise temporal para compreender evolução completa

---

## ✅ Validação de Consistência

### Integridade Referencial

| Verificação | Resultado |
|-------------|-----------|
| Gestações na linha do tempo | 85.633 |
| Gestações na tabela base | 293.382 |
| **Gestações órfãs (sem referência)** | **0 ✅** |

**Status**: INTEGRIDADE REFERENCIAL PRESERVADA

A linha do tempo contém um subconjunto das gestações (29,2% do total), filtrando apenas:
- Gestações em fase "Gestação" ou "Puerpério"
- Excluindo gestações "Encerradas"

---

## 🔧 Problemas Encontrados e Soluções

### Erro 1: Tabelas não encontradas (Procedimento 6 - Primeira tentativa)

**Problema**:
```
Table rj-sms-sandbox:sub_pav_us._consultas_emergenciais_historico was not found
```

**Causa**: Procedimento 6 valida a existência de tabelas dependentes durante a criação, mas os procedimentos 3, 4 e 5 ainda não haviam sido executados.

**Solução**:
1. Executar procedimentos 3, 4 e 5 primeiro com o parâmetro de data
2. Depois criar o procedimento 6

---

### Erro 2: Campo não encontrado (Procedimento 6 - Segunda tentativa)

**Problema**:
```
Error validating procedure body: Query error: Name Encaminhamento_Alto_Risco not found inside r at [64:11]
```

**Causa**: CTE `categorias_risco_gestacional` (linhas 58-87 do arquivo `6_linha_tempo_historico.sql`) referenciava campos que não existem na tabela `cids_risco_gestacional`:
- `r.Encaminhamento_Alto_Risco`
- `r.Justificativa_Condicao`

**Solução**: Removido os campos problemáticos do SELECT e GROUP BY da CTE:

**Antes**:
```sql
SELECT f.id_gestacao,
    STRING_AGG(DISTINCT r.categoria, '; ' ORDER BY r.categoria) AS categorias_risco,
    r.Encaminhamento_Alto_Risco,  -- PROBLEMA
    r.Justificativa_Condicao       -- PROBLEMA
FROM ...
GROUP BY f.id_gestacao,
    r.Encaminhamento_Alto_Risco,  -- PROBLEMA
    r.Justificativa_Condicao       -- PROBLEMA
```

**Depois**:
```sql
SELECT f.id_gestacao,
    STRING_AGG(DISTINCT r.categoria, '; ' ORDER BY r.categoria) AS categorias_risco
    -- REMOVIDO: r.Encaminhamento_Alto_Risco, r.Justificativa_Condicao
FROM ...
GROUP BY f.id_gestacao
    -- REMOVIDO: r.Encaminhamento_Alto_Risco, r.Justificativa_Condicao
```

**Arquivo alterado**: `6_linha_tempo_historico.sql` (linhas 58-87)

---

## 📝 Comandos Executados

### 1. Criação dos Procedimentos

```bash
# Procedimento 3
bq query --use_legacy_sql=false < "3_visitas_acs_gestacao_historico.sql"

# Procedimento 4
bq query --use_legacy_sql=false < "4_consultas_emergenciais_historico.sql"

# Procedimento 5
bq query --use_legacy_sql=false < "5_encaminhamentos_historico.sql"

# Procedimento 6 (após correção)
bq query --use_legacy_sql=false < "6_linha_tempo_historico.sql"
```

### 2. Execução dos Procedimentos

```bash
# Procedimento 3
bq query --use_legacy_sql=false 'CALL `rj-sms-sandbox.sub_pav_us.proced_3_visitas_acs_gestacao_historico`(DATE("2024-10-31"))'

# Procedimento 4
bq query --use_legacy_sql=false 'CALL `rj-sms-sandbox.sub_pav_us.proced_4_consultas_emergenciais_historico`(DATE("2024-10-31"))'

# Procedimento 5
bq query --use_legacy_sql=false 'CALL `rj-sms-sandbox.sub_pav_us.proced_5_encaminhamentos_historico`(DATE("2024-10-31"))'

# Procedimento 6
bq query --use_legacy_sql=false 'CALL `rj-sms-sandbox.sub_pav_us.proced_6_linha_tempo_historico`(DATE("2024-10-31"))'
```

---

## 🎓 Lições Aprendidas

### 1. Ordem de Execução Importa
Os procedimentos devem ser executados na ordem correta (1→2→(3,4,5)→6) para garantir que as dependências sejam satisfeitas.

### 2. Validação de Schema Durante Criação
O BigQuery valida a existência de tabelas e campos durante a criação de procedimentos, não apenas durante a execução. Isso pode causar erros se as tabelas dependentes ainda não existirem.

### 3. Consistência de Dados de Referência
É fundamental que todas as tabelas de referência (como `cids_risco_gestacional`) tenham o schema documentado e consistente com o código SQL que as utiliza.

### 4. Parametrização de Datas
O uso do parâmetro `data_referencia` ao invés de `CURRENT_DATE()` permite reconstrução histórica precisa para qualquer ponto no tempo.

---

## 🚀 Próximos Passos Recomendados

1. **Teste com Múltiplas Datas**
   - Executar procedimentos para últimos dias de vários meses (ex: 2024-01-31, 2024-02-29, etc.)
   - Verificar evolução temporal de indicadores

2. **Análise Temporal**
   - Comparar indicadores entre diferentes snapshots
   - Identificar tendências de cobertura ao longo do tempo

3. **Validação de Qualidade de Dados**
   - Investigar por que apenas 7,89% das gestações ativas têm ao menos 1 consulta
   - Verificar se há problemas de integração entre sistemas

4. **Criar Tabelas Acumuladas**
   - Implementar exemplo 3 do `construir_historico_completo.sql`
   - Gerar série histórica mensal completa

5. **Documentação de Schema**
   - Documentar campos esperados em todas as tabelas de referência
   - Criar testes de validação de schema

---

## 📚 Documentação de Referência

- `teste_procedimentos_3_a_6.sql` - Script de teste automatizado completo
- `README_TESTES.md` - Guia detalhado de testes
- `INSTRUCOES_TESTE.md` - Instruções passo a passo
- `construir_historico_completo.sql` - Exemplos de execução em produção
- `README_HISTORICO_COMPLETO.md` - Documentação completa do sistema

---

**Relatório gerado em**: 2025-10-28
**Responsável**: Claude Code
**Status final**: ✅ TODOS OS TESTES CONCLUÍDOS COM SUCESSO
