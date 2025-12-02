# Guia de Testes - Procedimentos Históricos de Pré-Natal

## 📋 Visão Geral

Este documento descreve como testar os 6 procedimentos parametrizados do pipeline histórico de acompanhamento pré-natal no BigQuery.

## ✅ Pré-requisitos

Antes de executar os testes:

1. **Acesso ao BigQuery**: Permissões para executar queries no projeto `rj-sms-sandbox`
2. **Procedimentos criados**: Todos os 6 procedimentos devem estar criados no dataset `sub_pav_us`
3. **Dados disponíveis**: Tabelas fonte devem ter dados para a data de teste escolhida

## 🧪 Histórico de Testes

### Testes Anteriores (Concluídos com Sucesso)

#### ✅ Procedimento 1: Gestações Histórico
- **Data testada**: 2024-10-31
- **Status**: ✅ Aprovado
- **Resultados**:
  - Registros criados com sucesso
  - Todas as fases (Gestação, Puerpério, Encerrada) identificadas corretamente
  - Cálculo de DPP e trimestres validado

#### ✅ Procedimento 2: Atendimentos Pré-Natal APS
- **Data testada**: 2024-10-31
- **Status**: ✅ Aprovado
- **Resultados**:
  - Dependência com procedimento 1 validada
  - Cálculos antropométricos (IMC, ganho de peso) corretos
  - Classificação de pressão arterial funcionando
  - Numeração de consultas sequencial correta

## 🚀 Como Executar os Testes

### Opção 1: Teste Completo (Procedimentos 3-6)

Use o script `teste_procedimentos_3_a_6.sql` para testar todos os procedimentos restantes de uma vez:

```sql
-- 1. Abra o BigQuery Console
-- 2. Copie todo o conteúdo de teste_procedimentos_3_a_6.sql
-- 3. Cole no editor de queries
-- 4. Execute (Ctrl+Enter ou botão "Run")
```

Este script irá:
- ✅ Validar pré-requisitos (procedimentos 1 e 2 executados)
- ✅ Executar procedimento 3 (Visitas ACS)
- ✅ Executar procedimento 4 (Consultas Emergenciais)
- ✅ Executar procedimento 5 (Encaminhamentos SISREG)
- ✅ Executar procedimento 6 (Linha do Tempo)
- ✅ Validar cada procedimento individualmente
- ✅ Verificar consistência entre tabelas
- ✅ Gerar resumo consolidado

### Opção 2: Teste Individual por Procedimento

Se preferir testar um procedimento de cada vez:

#### Teste Procedimento 3: Visitas ACS

```sql
DECLARE data_ref DATE DEFAULT DATE('2024-10-31');

-- Executar procedimento
CALL `rj-sms-sandbox.sub_pav_us.proced_3_visitas_acs_gestacao_historico`(data_ref);

-- Validar resultados
SELECT
    COUNT(*) AS total_visitas,
    COUNT(DISTINCT id_gestacao) AS gestacoes_com_visita,
    COUNT(DISTINCT id_paciente) AS pacientes_com_visita,
    ROUND(AVG(numero_visita), 2) AS media_visitas_por_gestacao
FROM `rj-sms-sandbox.sub_pav_us._visitas_acs_gestacao_historico`
WHERE data_snapshot = data_ref;
```

**Resultados esperados:**
- ✅ `total_visitas` > 0
- ✅ `gestacoes_com_visita` ≤ total de gestações do procedimento 1
- ✅ `numero_visita` sequencial começando em 1 para cada gestação

#### Teste Procedimento 4: Consultas Emergenciais

```sql
DECLARE data_ref DATE DEFAULT DATE('2024-10-31');

-- Executar procedimento
CALL `rj-sms-sandbox.sub_pav_us.proced_4_consultas_emergenciais_historico`(data_ref);

-- Validar resultados
SELECT
    COUNT(*) AS total_consultas_emergencia,
    COUNT(DISTINCT id_gestacao) AS gestacoes_com_emergencia,
    ROUND(AVG(idade_gestacional_consulta), 2) AS media_ig_semanas
FROM `rj-sms-sandbox.sub_pav_us._consultas_emergenciais_historico`
WHERE data_snapshot = data_ref;

-- Principais CIDs
SELECT
    cids_emergencia,
    COUNT(*) AS total_ocorrencias
FROM `rj-sms-sandbox.sub_pav_us._consultas_emergenciais_historico`
WHERE data_snapshot = data_ref
  AND cids_emergencia IS NOT NULL
GROUP BY cids_emergencia
ORDER BY total_ocorrencias DESC
LIMIT 10;
```

**Resultados esperados:**
- ✅ `total_consultas_emergencia` >= 0 (pode ser 0 se não houver emergências)
- ✅ `idade_gestacional_consulta` entre 0 e 44 semanas
- ✅ CIDs devem estar no formato ICD-10

#### Teste Procedimento 5: Encaminhamentos SISREG

```sql
DECLARE data_ref DATE DEFAULT DATE('2024-10-31');

-- Executar procedimento
CALL `rj-sms-sandbox.sub_pav_us.proced_5_encaminhamentos_historico`(data_ref);

-- Validar resultados
SELECT
    COUNT(*) AS total_encaminhamentos,
    COUNT(DISTINCT id_gestacao) AS gestacoes_com_encaminhamento,
    COUNT(DISTINCT sisreg_primeira_procedimento_id) AS tipos_procedimentos
FROM `rj-sms-sandbox.sub_pav_us._encaminhamentos_historico`
WHERE data_snapshot = data_ref;

-- Status das solicitações
SELECT
    sisreg_primeira_status,
    COUNT(*) AS total
FROM `rj-sms-sandbox.sub_pav_us._encaminhamentos_historico`
WHERE data_snapshot = data_ref
GROUP BY sisreg_primeira_status;
```

**Resultados esperados:**
- ✅ `total_encaminhamentos` >= 0 (apenas gestações em fase 'Gestação')
- ✅ `sisreg_primeira_procedimento_id` deve estar nos valores: '0703844','0703886','0737024','0710301','0710128'
- ✅ Apenas primeira solicitação de cada gestação (sem duplicatas)

#### Teste Procedimento 6: Linha do Tempo

```sql
DECLARE data_ref DATE DEFAULT DATE('2024-10-31');

-- Executar procedimento
CALL `rj-sms-sandbox.sub_pav_us.proced_6_linha_tempo_historico`(data_ref);

-- Validação completa
SELECT
    COUNT(*) AS total_gestacoes,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(fase_atual = 'Puerpério') AS em_puerperio,
    ROUND(AVG(qtd_consultas_realizadas), 2) AS media_consultas,
    ROUND(AVG(qtd_visitas_acs), 2) AS media_visitas,
    COUNTIF(hipertensao_total = 1) AS com_hipertensao,
    COUNTIF(diabetes_total = 1) AS com_diabetes
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_ref;

-- Indicadores de cobertura
SELECT
    ROUND(100.0 * COUNTIF(tem_primeira_consulta_primeiro_trimestre = 1) / COUNT(*), 2) AS perc_consulta_1tri,
    ROUND(100.0 * COUNTIF(qtd_consultas_realizadas >= 6) / COUNT(*), 2) AS perc_adequacao_6_consultas,
    ROUND(100.0 * COUNTIF(qtd_visitas_acs >= 1) / COUNT(*), 2) AS perc_com_visita_acs
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_ref
  AND fase_atual = 'Gestação';
```

**Resultados esperados:**
- ✅ `total_gestacoes` = soma de gestações ativas + puerpério (não inclui "Encerrada")
- ✅ `qtd_consultas_realizadas` deve corresponder aos dados do procedimento 2
- ✅ `qtd_visitas_acs` deve corresponder aos dados do procedimento 3
- ✅ `qtd_consultas_emergenciais` deve corresponder aos dados do procedimento 4
- ✅ Todos os indicadores booleanos devem ser 0 ou 1

## 🔍 Validações de Consistência

### Consistência Referencial

Verificar se todas as gestações na linha do tempo existem na tabela base:

```sql
WITH gestacoes_linha_tempo AS (
    SELECT DISTINCT id_gestacao
    FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
    WHERE data_snapshot = DATE('2024-10-31')
),
gestacoes_base AS (
    SELECT DISTINCT id_gestacao
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = DATE('2024-10-31')
)
SELECT
    (SELECT COUNT(*) FROM gestacoes_linha_tempo) AS total_linha_tempo,
    (SELECT COUNT(*) FROM gestacoes_base) AS total_gestacoes_base,
    (SELECT COUNT(*) FROM gestacoes_linha_tempo
     WHERE id_gestacao NOT IN (SELECT id_gestacao FROM gestacoes_base)) AS gestacoes_orfas;
```

**Resultado esperado:**
- ✅ `gestacoes_orfas` = 0 (nenhuma gestação órfã)

### Consistência de Contadores

Verificar se os contadores da linha do tempo correspondem aos dados reais:

```sql
SELECT
    lt.id_gestacao,
    lt.qtd_consultas_realizadas AS contador_consultas,
    COUNT(DISTINCT atd.data_consulta) AS consultas_reais,
    lt.qtd_visitas_acs AS contador_visitas,
    COUNT(DISTINCT vis.entrada_data) AS visitas_reais
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico` lt
LEFT JOIN `rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico` atd
    ON lt.id_gestacao = atd.id_gestacao AND atd.data_snapshot = DATE('2024-10-31')
LEFT JOIN `rj-sms-sandbox.sub_pav_us._visitas_acs_gestacao_historico` vis
    ON lt.id_gestacao = vis.id_gestacao AND vis.data_snapshot = DATE('2024-10-31')
WHERE lt.data_snapshot = DATE('2024-10-31')
GROUP BY lt.id_gestacao, lt.qtd_consultas_realizadas, lt.qtd_visitas_acs
HAVING
    lt.qtd_consultas_realizadas != COUNT(DISTINCT atd.data_consulta)
    OR lt.qtd_visitas_acs != COUNT(DISTINCT vis.entrada_data)
LIMIT 10;
```

**Resultado esperado:**
- ✅ Nenhuma linha retornada (todos os contadores consistentes)

## 📊 Interpretação dos Resultados

### Procedimento 3: Visitas ACS

| Métrica | Valor Típico | Interpretação |
|---------|--------------|---------------|
| Taxa de cobertura | 30-70% | % de gestações com ao menos 1 visita |
| Média de visitas | 2-5 | Visitas por gestação durante período |

### Procedimento 4: Consultas Emergenciais

| Métrica | Valor Típico | Interpretação |
|---------|--------------|---------------|
| Taxa de emergência | 10-30% | % de gestações com consulta emergencial |
| IG média | 20-28 semanas | Idade gestacional mais comum nas emergências |

### Procedimento 5: Encaminhamentos SISREG

| Métrica | Valor Típico | Interpretação |
|---------|--------------|---------------|
| Taxa de encaminhamento | 15-40% | % de gestações encaminhadas para alto risco |
| Status comum | AGUARDANDO_REGULACAO | Maioria das solicitações ainda em fila |

### Procedimento 6: Linha do Tempo

| Indicador | Meta MS | Interpretação |
|-----------|---------|---------------|
| Consulta no 1º trimestre | ≥75% | Início precoce do pré-natal |
| Adequação (≥6 consultas) | ≥60% | Cobertura de consultas |
| Prevalência HAS | 5-15% | Hipertensão na gestação |
| Prevalência Diabetes | 3-10% | Diabetes gestacional |

## ⚠️ Problemas Comuns e Soluções

### Erro: "Procedure not found"

**Causa**: Procedimento não foi criado no BigQuery

**Solução**:
```sql
-- Execute o arquivo SQL correspondente para criar o procedimento
-- Exemplo para procedimento 3:
-- Copie todo o conteúdo de 3_visitas_acs_gestacao_historico.sql
-- Cole no BigQuery e execute
```

### Erro: "Table not found: _gestacoes_historico"

**Causa**: Procedimentos 1 e 2 não foram executados

**Solução**:
```sql
-- Execute primeiro os procedimentos 1 e 2
DECLARE data_ref DATE DEFAULT DATE('2024-10-31');
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_ref);
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(data_ref);
```

### Retorno de 0 registros

**Causa**: Não há dados para a data de referência escolhida

**Solução**:
```sql
-- Tente uma data mais recente ou verifique disponibilidade de dados
-- Consulta para verificar datas disponíveis:
SELECT
    MIN(entrada_data) AS data_mais_antiga,
    MAX(entrada_data) AS data_mais_recente
FROM `rj-sms.saude_historico_clinico.episodio_assistencial`
WHERE prontuario.fornecedor IN ('vitacare', 'vitai');
```

### Inconsistência nos contadores

**Causa**: Dados foram alterados entre execuções de procedimentos

**Solução**:
```sql
-- Re-execute TODOS os procedimentos na ordem correta com a mesma data
DECLARE data_ref DATE DEFAULT DATE('2024-10-31');
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_ref);
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(data_ref);
CALL `rj-sms-sandbox.sub_pav_us.proced_3_visitas_acs_gestacao_historico`(data_ref);
CALL `rj-sms-sandbox.sub_pav_us.proced_4_consultas_emergenciais_historico`(data_ref);
CALL `rj-sms-sandbox.sub_pav_us.proced_5_encaminhamentos_historico`(data_ref);
CALL `rj-sms-sandbox.sub_pav_us.proced_6_linha_tempo_historico`(data_ref);
```

## 📝 Checklist de Testes

Após executar os testes, marque as validações concluídas:

### Procedimento 3: Visitas ACS
- [ ] Procedimento executado sem erros
- [ ] Total de visitas > 0
- [ ] Numeração de visitas sequencial por gestação
- [ ] Todas as visitas dentro do período gestacional
- [ ] Apenas ACS no campo profissional

### Procedimento 4: Consultas Emergenciais
- [ ] Procedimento executado sem erros
- [ ] IG calculada corretamente (0-44 semanas)
- [ ] CIDs no formato correto
- [ ] Apenas consultas "Emergência" e fornecedor "vitai"
- [ ] Numeração de consultas sequencial

### Procedimento 5: Encaminhamentos SISREG
- [ ] Procedimento executado sem erros
- [ ] Apenas primeira solicitação por gestação
- [ ] Procedimentos válidos (5 códigos específicos)
- [ ] Apenas gestações em fase "Gestação"
- [ ] Match CPF correto

### Procedimento 6: Linha do Tempo
- [ ] Procedimento executado sem erros
- [ ] Total de gestações = ativas + puerpério
- [ ] Contadores consistentes com tabelas fonte
- [ ] Todos os indicadores booleanos = 0 ou 1
- [ ] Fases corretas (Gestação/Puerpério)
- [ ] Nenhuma gestação órfã (sem referência na tabela 1)

### Consistência Geral
- [ ] Todas as 6 tabelas criadas para o snapshot
- [ ] Integridade referencial validada
- [ ] Contadores da linha do tempo corretos
- [ ] Resumo consolidado gerado

## 🎯 Próximos Passos

Após testes bem-sucedidos:

1. **Teste com múltiplas datas**: Execute para diferentes snapshots (último dia de cada mês)
2. **Criar tabelas acumuladas**: Use o script `construir_historico_completo.sql` exemplo 3
3. **Análises temporais**: Explore evolução de indicadores ao longo do tempo
4. **Documentação**: Atualize este README com resultados específicos do seu ambiente

## 📚 Referências

- `construir_historico_completo.sql` - Exemplos de execução completa
- `README_HISTORICO_COMPLETO.md` - Documentação completa do sistema
- `CLAUDE.md` - Guia técnico para desenvolvedores
