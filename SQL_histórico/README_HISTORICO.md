# Sistema de Histórico de Gestações

## Visão Geral

Este documento explica como usar o sistema parametrizado de histórico de gestações que permite capturar snapshots dos dados em datas específicas, possibilitando análises temporais e construção de séries históricas.

## Diferença entre as Versões

### Versão Original (`proced_1_gestacoes`)
- Usa `CURRENT_DATE()` em todas as verificações
- Sempre retorna o estado atual dos dados
- Não permite análise histórica

### Versão Parametrizada (`proced_1_gestacoes_historico`)
- Recebe parâmetro `data_referencia DATE`
- Calcula estados como se estivéssemos naquela data específica
- Permite reconstruir histórico e fazer análises temporais
- Adiciona coluna `data_snapshot` na saída

## Alterações Realizadas

Todas as ocorrências de `CURRENT_DATE()` foram substituídas por `data_referencia`:

| Localização | Uso Original | Novo Uso |
|-------------|--------------|----------|
| Cálculo de idade | `DATE_DIFF(CURRENT_DATE(), nascimento, YEAR)` | `DATE_DIFF(data_referencia, nascimento, YEAR)` |
| Data fim efetiva | `... <= CURRENT_DATE()` | `... <= data_referencia` |
| Fase gestação | `... > CURRENT_DATE()` | `... > data_referencia` |
| Fase puerpério | `DATE_DIFF(CURRENT_DATE(), data_fim, DAY)` | `DATE_DIFF(data_referencia, data_fim, DAY)` |
| Cálculo trimestre | `DATE_DIFF(CURRENT_DATE(), data_inicio, WEEK)` | `DATE_DIFF(data_referencia, data_inicio, WEEK)` |
| Equipe durante gestação | `COALESCE(data_fim, CURRENT_DATE())` | `COALESCE(data_fim, data_referencia)` |

## Como Usar

### 1. Executar para uma data específica

```sql
-- Gerar snapshot para 31 de Janeiro de 2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-01-31'));

-- Ver resultado
SELECT * FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2024-01-31');
```

### 2. Construir série histórica mensal

```sql
-- Janeiro
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-01-31'));
INSERT INTO gestacoes_historico_acumulado SELECT * FROM _gestacoes_historico;

-- Fevereiro
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-02-29'));
INSERT INTO gestacoes_historico_acumulado SELECT * FROM _gestacoes_historico;

-- Março
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-03-31'));
INSERT INTO gestacoes_historico_acumulado SELECT * FROM _gestacoes_historico;
```

### 3. Automatizar com loop

```sql
DECLARE data_inicial DATE DEFAULT DATE('2024-01-31');
DECLARE data_final DATE DEFAULT DATE('2024-12-31');
DECLARE data_atual DATE;

SET data_atual = data_inicial;

WHILE data_atual <= data_final DO
    CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_atual);
    INSERT INTO gestacoes_historico_acumulado SELECT * FROM _gestacoes_historico;
    SET data_atual = LAST_DAY(DATE_ADD(data_atual, INTERVAL 1 MONTH));
END WHILE;
```

## Casos de Uso

### 1. Análise de Tendências

```sql
-- Ver evolução do número de gestações por mês
SELECT
    data_snapshot,
    COUNT(*) as total_gestacoes,
    COUNTIF(fase_atual = 'Gestação') as em_gestacao,
    COUNTIF(fase_atual = 'Puerpério') as em_puerperio
FROM gestacoes_historico_acumulado
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### 2. Acompanhar Gestação Individual

```sql
-- Ver como uma gestação específica evoluiu ao longo do tempo
SELECT
    data_snapshot,
    fase_atual,
    trimestre_atual_gestacao,
    DATE_DIFF(data_snapshot, data_inicio, WEEK) as semanas
FROM gestacoes_historico_acumulado
WHERE id_gestacao = 'PACIENTE-1'
ORDER BY data_snapshot;
```

### 3. Identificar Mudanças de Fase

```sql
-- Ver gestações que mudaram de trimestre entre dois meses
WITH
    janeiro AS (
        SELECT * FROM gestacoes_historico_acumulado
        WHERE data_snapshot = DATE('2024-01-31')
    ),
    fevereiro AS (
        SELECT * FROM gestacoes_historico_acumulado
        WHERE data_snapshot = DATE('2024-02-29')
    )
SELECT
    f.id_gestacao,
    f.nome,
    j.trimestre_atual_gestacao AS trimestre_janeiro,
    f.trimestre_atual_gestacao AS trimestre_fevereiro
FROM fevereiro f
JOIN janeiro j ON f.id_gestacao = j.id_gestacao
WHERE j.trimestre_atual_gestacao != f.trimestre_atual_gestacao;
```

### 4. Relatórios Retroativos

```sql
-- Gerar relatório como se estivéssemos em 30/06/2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-06-30'));

SELECT
    fase_atual,
    trimestre_atual_gestacao,
    COUNT(*) as total,
    AVG(idade_gestante) as idade_media
FROM _gestacoes_historico
WHERE fase_atual = 'Gestação'
GROUP BY fase_atual, trimestre_atual_gestacao;
```

## Estrutura da Tabela Histórica Acumulada

```sql
CREATE TABLE `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado` (
    data_snapshot DATE,              -- Data do snapshot
    id_hci STRING,
    id_gestacao STRING,
    id_paciente STRING,
    cpf STRING,
    nome STRING,
    idade_gestante INT64,
    numero_gestacao INT64,
    data_inicio DATE,
    data_fim DATE,
    data_fim_efetiva DATE,
    dpp DATE,
    fase_atual STRING,               -- Estado na data_snapshot
    trimestre_atual_gestacao STRING, -- Trimestre na data_snapshot
    equipe_nome STRING,
    clinica_nome STRING
)
PARTITION BY data_snapshot           -- Otimização para consultas temporais
CLUSTER BY id_paciente, fase_atual; -- Otimização para consultas por paciente
```

## Boas Práticas

### 1. Frequência de Snapshots

- **Diário**: Para monitoramento contínuo e detalhado
- **Semanal**: Para acompanhamento regular com menor volume
- **Mensal**: Para análises de tendências de longo prazo
- **Específico**: Para auditorias ou análises pontuais

### 2. Retenção de Dados

```sql
-- Manter apenas últimos 12 meses
DELETE FROM gestacoes_historico_acumulado
WHERE data_snapshot < DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH);
```

### 3. Validação de Dados

```sql
-- Verificar consistência entre snapshots
WITH comparacao AS (
    SELECT
        data_snapshot,
        id_gestacao,
        fase_atual,
        LAG(fase_atual) OVER (PARTITION BY id_gestacao ORDER BY data_snapshot) as fase_anterior
    FROM gestacoes_historico_acumulado
)
SELECT *
FROM comparacao
WHERE fase_atual = 'Gestação' AND fase_anterior = 'Encerrada' -- Alerta: regressão impossível
;
```

### 4. Performance

- Use particionamento por `data_snapshot` para queries temporais
- Use clustering por `id_paciente` e `fase_atual` para filtros comuns
- Considere materialized views para agregações frequentes
- Execute snapshots em horários de baixo uso

## Limitações e Considerações

### 1. Dados Retroativos

A reconstrução de histórico é baseada nos dados **atualmente** disponíveis no sistema. Se dados foram alterados, excluídos ou corrigidos, o histórico retroativo refletirá o estado atual dos dados, não necessariamente o estado que existia naquela data específica.

### 2. Performance

Executar o procedimento para muitas datas pode ser custoso. Considere:
- Executar em lotes pequenos
- Usar slots de processamento dedicados
- Agendar para horários de baixa demanda

### 3. Armazenamento

Cada snapshot duplica os dados. Para 1000 gestações e snapshots mensais por 1 ano:
- 1000 gestações × 12 meses = 12.000 registros

Planeje capacidade de armazenamento adequadamente.

## Migração da Versão Original

Se você já está usando `proced_1_gestacoes`, pode:

1. **Manter ambas as versões**: Use original para dados atuais, histórico para análises temporais
2. **Migrar completamente**: Substitua a versão original pela parametrizada
3. **Híbrido**: Use versão parametrizada com `CURRENT_DATE()` como padrão

```sql
-- Executar versão histórica com data atual (equivalente à original)
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(CURRENT_DATE());
```

## Exemplos de Análises

### Dashboard Executivo

```sql
-- Métricas mensais para dashboard
SELECT
    DATE_TRUNC(data_snapshot, MONTH) as mes,
    COUNT(DISTINCT id_paciente) as total_pacientes,
    COUNTIF(fase_atual = 'Gestação') as gestacoes_ativas,
    COUNTIF(fase_atual = 'Puerpério') as em_puerperio,
    COUNTIF(trimestre_atual_gestacao = '1º trimestre') as primeiro_trimestre,
    COUNTIF(trimestre_atual_gestacao = '2º trimestre') as segundo_trimestre,
    COUNTIF(trimestre_atual_gestacao = '3º trimestre') as terceiro_trimestre
FROM gestacoes_historico_acumulado
GROUP BY mes
ORDER BY mes;
```

### Análise de Coorte

```sql
-- Acompanhar coorte de gestações que iniciaram em janeiro
WITH coorte_janeiro AS (
    SELECT DISTINCT id_gestacao
    FROM gestacoes_historico_acumulado
    WHERE data_snapshot = DATE('2024-01-31')
      AND fase_atual = 'Gestação'
      AND trimestre_atual_gestacao = '1º trimestre'
)
SELECT
    h.data_snapshot,
    COUNT(*) as total_coorte,
    COUNTIF(h.fase_atual = 'Gestação') as ainda_gestantes,
    COUNTIF(h.fase_atual = 'Puerpério') as em_puerperio,
    COUNTIF(h.fase_atual = 'Encerrada') as encerradas
FROM coorte_janeiro c
JOIN gestacoes_historico_acumulado h ON c.id_gestacao = h.id_gestacao
GROUP BY h.data_snapshot
ORDER BY h.data_snapshot;
```

## Suporte

Para questões sobre:
- **Lógica de negócio**: Consulte `CLAUDE.md` na raiz do projeto
- **Performance**: Verifique plano de execução e considere otimizações de índices
- **Dados inconsistentes**: Execute queries de validação na seção "Boas Práticas"
