# Sistema de Histórico de Atendimentos Pré-Natal

## Visão Geral

Este documento explica como usar o sistema parametrizado de histórico de atendimentos pré-natal que depende dos snapshots de gestações e permite análises temporais completas do acompanhamento pré-natal.

## Arquitetura de Dependências

```
proced_1_gestacoes_historico (data_referencia)
    ↓ gera
_gestacoes_historico (com data_snapshot)
    ↓ alimenta
proced_2_atd_prenatal_aps_historico (data_referencia)
    ↓ gera
_atendimentos_prenatal_aps_historico (com data_snapshot)
```

**IMPORTANTE**: Sempre executar `proced_1_gestacoes_historico` ANTES de `proced_2_atd_prenatal_aps_historico` para a mesma data.

## Diferença entre as Versões

### Versão Original (`proced_2_atd_prenatal_aps`)
- Usa `CURRENT_DATE()` em 2 localizações
- Depende de `_gestacoes` (tabela atual)
- Sempre retorna atendimentos baseados no estado atual
- Não permite análise histórica

### Versão Parametrizada (`proced_2_atd_prenatal_aps_historico`)
- Recebe parâmetro `data_referencia DATE`
- Depende de `_gestacoes_historico` filtrado por `data_snapshot`
- Calcula estados como se estivéssemos naquela data específica
- Permite reconstruir histórico de atendimentos
- Adiciona coluna `data_snapshot` na saída

## Alterações Realizadas

| Localização | Uso Original | Novo Uso |
|-------------|--------------|----------|
| CTE alturas_filtradas (linha 76) | `COALESCE(mt.data_fim_efetiva, CURRENT_DATE())` | `COALESCE(mt.data_fim_efetiva, data_referencia)` |
| CTE atendimentos_gestacao (linha 204) | `BETWEEN ... AND COALESCE(..., CURRENT_DATE())` | `BETWEEN ... AND COALESCE(..., data_referencia)` |
| CTE marcadores_temporais | `FROM _gestacoes` | `FROM _gestacoes_historico WHERE data_snapshot = data_referencia` |
| SELECT final | - | `data_referencia AS data_snapshot` (nova coluna) |

## Como Usar

### 1. Executar para uma data específica

```sql
-- IMPORTANTE: Executar NA ORDEM

-- Passo 1: Gerar snapshot de gestações
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-10-31'));

-- Passo 2: Gerar atendimentos baseados nesse snapshot
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(DATE('2024-10-31'));

-- Ver resultado
SELECT * FROM `rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico`
WHERE data_snapshot = DATE('2024-10-31');
```

### 2. Construir série histórica mensal

```sql
-- Para cada mês, executar AMBOS os procedimentos

-- Janeiro
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-01-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(DATE('2024-01-31'));
INSERT INTO atendimentos_prenatal_historico_acumulado
SELECT * FROM _atendimentos_prenatal_aps_historico;

-- Fevereiro
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-02-29'));
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(DATE('2024-02-29'));
INSERT INTO atendimentos_prenatal_historico_acumulado
SELECT * FROM _atendimentos_prenatal_aps_historico;
```

### 3. Automatizar com loop

```sql
DECLARE data_inicial DATE DEFAULT DATE('2024-01-31');
DECLARE data_final DATE DEFAULT DATE('2024-12-31');
DECLARE data_atual DATE;

SET data_atual = data_inicial;

WHILE data_atual <= data_final DO
    -- Passo 1: Gestações
    CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_atual);

    -- Passo 2: Atendimentos
    CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(data_atual);

    -- Passo 3: Acumular
    INSERT INTO atendimentos_prenatal_historico_acumulado
    SELECT * FROM _atendimentos_prenatal_aps_historico;

    SET data_atual = LAST_DAY(DATE_ADD(data_atual, INTERVAL 1 MONTH));
END WHILE;
```

## Lógica de Negócio

### Cálculo de Peso Inicial
- Busca peso entre **-180 e +84 dias** da data de início da gestação
- Seleciona o peso **mais próximo** da data de início

### Cálculo de Altura
- **Preferencial**: Moda de alturas entre 1 ano antes e fim da gestação
- **Fallback**: Moda de todas as alturas disponíveis

### Cálculo de IMC Inicial
```
IMC = peso_inicio / (altura_m)²
```

Classificação:
- < 18: Baixo peso
- 18-24.9: Eutrófico
- 25-29.9: Sobrepeso
- ≥ 30: Obesidade

### Filtro de Atendimentos
- **Subtipo**: "Atendimento SOAP"
- **Fornecedor**: Vitacare
- **Situação CID**: ATIVO
- **Categorias profissionais**: 12 especialidades de APS (médicos ESF, enfermeiros, obstetras)

### Cálculo de IG (Idade Gestacional)
```sql
IG = DATE_DIFF(entrada_data, data_inicio, WEEK)
```

### Trimestre da Consulta
- Trimestre 1: IG ≤ 13 semanas
- Trimestre 2: IG 14-27 semanas
- Trimestre 3: IG ≥ 28 semanas

### Ganho de Peso Acumulado
```sql
ganho_peso_acumulado = peso_consulta - peso_inicio
```

## Estrutura da Tabela Histórica Acumulada

```sql
CREATE TABLE atendimentos_prenatal_historico_acumulado (
    data_snapshot DATE,                  -- Data do snapshot
    id_gestacao STRING,
    id_paciente STRING,
    data_consulta DATE,
    numero_consulta INT64,              -- Sequência de consultas
    ig_consulta INT64,                  -- Idade gestacional em semanas
    trimestre_consulta INT64,           -- 1, 2 ou 3
    fase_atual STRING,                  -- Gestação/Puerpério/Encerrada

    -- Dados antropométricos iniciais
    peso_inicio FLOAT64,
    altura_inicio FLOAT64,
    imc_inicio FLOAT64,
    classificacao_imc_inicio STRING,

    -- Dados da consulta
    peso FLOAT64,
    imc_consulta FLOAT64,
    ganho_peso_acumulado FLOAT64,
    pressao_sistolica INT64,
    pressao_diastolica INT64,

    -- Dados clínicos
    descricao_s STRING,                 -- Motivo do atendimento
    cid STRING,
    desfecho STRING,
    prescricoes STRING,

    -- Contexto do atendimento
    estabelecimento STRING,
    profissional_nome STRING,
    profissional_categoria STRING
)
PARTITION BY data_snapshot
CLUSTER BY id_paciente, fase_atual;
```

## Casos de Uso

### 1. Evolução da Cobertura de Pré-Natal

```sql
SELECT
    data_snapshot,
    COUNT(*) as total_atendimentos,
    COUNT(DISTINCT id_gestacao) as gestacoes_atendidas,
    AVG(numero_consulta) as media_consultas_por_gestacao
FROM atendimentos_prenatal_historico_acumulado
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### 2. Análise de Adequação do Número de Consultas

```sql
SELECT
    data_snapshot,
    COUNTIF(numero_consulta >= 6) as com_6_ou_mais,
    COUNT(*) as total_gestacoes,
    ROUND(COUNTIF(numero_consulta >= 6) / COUNT(*) * 100, 1) as percentual_adequado
FROM (
    SELECT data_snapshot, id_gestacao, MAX(numero_consulta) as numero_consulta
    FROM atendimentos_prenatal_historico_acumulado
    GROUP BY data_snapshot, id_gestacao
)
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### 3. Evolução do Ganho de Peso por Classificação IMC

```sql
SELECT
    data_snapshot,
    classificacao_imc_inicio,
    COUNT(*) as total,
    AVG(ganho_peso_acumulado) as ganho_medio,
    STDDEV(ganho_peso_acumulado) as desvio_padrao
FROM atendimentos_prenatal_historico_acumulado
WHERE ganho_peso_acumulado IS NOT NULL
GROUP BY data_snapshot, classificacao_imc_inicio
ORDER BY data_snapshot, classificacao_imc_inicio;
```

### 4. Detecção de Hipertensão ao Longo do Tempo

```sql
SELECT
    data_snapshot,
    COUNT(*) as total_afericoes,
    COUNTIF(pressao_sistolica >= 140 OR pressao_diastolica >= 90) as hipertensas,
    ROUND(COUNTIF(pressao_sistolica >= 140 OR pressao_diastolica >= 90) / COUNT(*) * 100, 1) as percentual_hipertensao
FROM atendimentos_prenatal_historico_acumulado
WHERE pressao_sistolica IS NOT NULL
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### 5. Distribuição de Consultas por Trimestre

```sql
SELECT
    data_snapshot,
    trimestre_consulta,
    COUNT(*) as total_consultas,
    AVG(ig_consulta) as ig_media,
    COUNT(DISTINCT id_gestacao) as gestacoes_atendidas
FROM atendimentos_prenatal_historico_acumulado
GROUP BY data_snapshot, trimestre_consulta
ORDER BY data_snapshot, trimestre_consulta;
```

### 6. Acompanhamento Longitudinal de Gestação

```sql
SELECT
    data_snapshot,
    data_consulta,
    numero_consulta,
    ig_consulta,
    trimestre_consulta,
    peso,
    ganho_peso_acumulado,
    pressao_sistolica,
    pressao_diastolica,
    cid,
    prescricoes
FROM atendimentos_prenatal_historico_acumulado
WHERE id_gestacao = 'GESTACAO_ID_EXEMPLO'
ORDER BY data_snapshot, data_consulta;
```

## Boas Práticas

### 1. Ordem de Execução

✅ **SEMPRE** executar na ordem:
1. `proced_1_gestacoes_historico(data)`
2. `proced_2_atd_prenatal_aps_historico(data)`

❌ **NUNCA** executar atendimentos sem ter executado gestações primeiro para a mesma data.

### 2. Validação de Consistência

```sql
-- Verificar se todos os snapshots de atendimentos têm gestações correspondentes
SELECT DISTINCT data_snapshot
FROM atendimentos_prenatal_historico_acumulado
WHERE data_snapshot NOT IN (
    SELECT DISTINCT data_snapshot
    FROM gestacoes_historico_acumulado
);
-- Deve retornar vazio
```

### 3. Performance

- Use `PARTITION BY data_snapshot` para queries temporais
- Use `CLUSTER BY id_paciente, fase_atual` para filtros comuns
- Considere criar índices adicionais para consultas frequentes
- Execute em horários de baixo uso para grandes períodos

### 4. Retenção de Dados

```sql
-- Manter apenas últimos 24 meses
DELETE FROM atendimentos_prenatal_historico_acumulado
WHERE data_snapshot < DATE_SUB(CURRENT_DATE(), INTERVAL 24 MONTH);
```

## Limitações e Considerações

### 1. Dependência de Gestações

Os atendimentos históricos dependem dos snapshots de gestações. Se um snapshot de gestação não existir, os atendimentos não podem ser gerados para aquela data.

### 2. Dados Retroativos

Como na query de gestações, a reconstrução reflete o estado atual dos dados de atendimentos, não necessariamente como estavam naquela data.

### 3. Performance

A query de atendimentos é mais complexa que a de gestações, envolvendo múltiplas agregações e junções. Para grandes volumes:
- Execute em lotes pequenos
- Use slots de processamento dedicados
- Considere materializar CTEs intermediárias

### 4. Completude de Dados

Nem todas as gestações terão atendimentos registrados. Isso é normal e reflete a realidade da cobertura do pré-natal.

## Indicadores Calculáveis

Com o histórico de atendimentos, é possível calcular:

1. **Cobertura de Pré-Natal**: % de gestações com pelo menos 1 consulta
2. **Adequação de Consultas**: % de gestações com ≥ 6 consultas
3. **Início Precoce**: % de gestações com 1ª consulta no 1º trimestre
4. **Ganho de Peso Adequado**: Por classificação IMC inicial
5. **Controle de Hipertensão**: % de gestantes hipertensas identificadas
6. **Prescrições Adequadas**: Análise de suplementação (ácido fólico, ferro)

## Migração da Versão Original

Se você já usa `proced_2_atd_prenatal_aps`:

1. **Manter ambas**: Use original para dados atuais, histórico para análises temporais
2. **Migrar completamente**: Substitua pela versão parametrizada
3. **Híbrido**: Execute versão histórica com data atual

```sql
-- Executar versão histórica como se fosse a original
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(CURRENT_DATE());
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(CURRENT_DATE());
```

## Troubleshooting

### Erro: "Table not found: _gestacoes_historico"
**Solução**: Execute `proced_1_gestacoes_historico` primeiro.

### Resultado vazio
**Causas possíveis**:
- Snapshot de gestações não gerado para a data
- Nenhuma gestação tinha atendimentos naquela data
- Filtros muito restritivos

### Performance lenta
**Soluções**:
- Reduza o intervalo de datas
- Use particionamento e clustering
- Execute em horários de baixo uso
- Considere aumentar slots de processamento

## Suporte

Para questões sobre:
- **Lógica de negócio**: Consulte este documento e `CLAUDE.md`
- **Performance**: Verifique plano de execução e otimizações de índices
- **Dados inconsistentes**: Execute queries de validação
- **Dúvidas sobre indicadores**: Consulte Ministério da Saúde - Cadernos de Atenção Básica nº 32
