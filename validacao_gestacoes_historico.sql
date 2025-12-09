-- ============================================================
-- VALIDAÇÃO COMPLETA: Procedimento 1 - Gestações Histórico
-- ============================================================
-- Autor: Sistema de Validação Automatizada
-- Data: 2025-12-08
-- Propósito: Validação abrangente de _gestacoes_historico
--
-- EXECUÇÃO:
-- 1. Configure data_referencia (linha 15)
-- 2. Execute no BigQuery Console ou via bq CLI
-- 3. Analise resultados seção por seção
-- ============================================================

DECLARE data_referencia DATE DEFAULT DATE('2024-07-01');

-- ============================================================
-- SEÇÃO 1: PRÉ-REQUISITOS
-- ============================================================
SELECT '1. PRÉ-REQUISITOS' AS secao, 'Verificando existência de dados' AS acao;

-- ------------------------------------------------------------
-- Módulo 1.1: Verificar Existência de Dados
-- Valida se existem dados para a data_referencia especificada
-- ------------------------------------------------------------
SELECT
    '1.1' AS modulo,
    'Verificação de Dados' AS validacao,
    CASE
        WHEN COUNT(*) > 0 THEN CONCAT('PASS ✅ - ', CAST(COUNT(*) AS STRING), ' registros encontrados')
        ELSE 'FAIL ❌ - Nenhum registro encontrado para esta data'
    END AS status,
    1 AS valor_esperado,
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END AS valor_atual,
    CONCAT('Total de gestações: ', CAST(COUNT(*) AS STRING)) AS detalhes
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = data_referencia;


-- ============================================================
-- SEÇÃO 2: VALIDAÇÕES CRÍTICAS (OBRIGATÓRIAS)
-- ============================================================
SELECT '2. VALIDAÇÕES CRÍTICAS' AS secao, 'Validações obrigatórias para aprovação' AS acao;

-- ------------------------------------------------------------
-- Módulo 2.1: Duplicatas
-- CRÍTICO: Zero gestações duplicadas (mesmo id_gestacao no snapshot)
-- Threshold: 0 duplicatas permitidas
-- ------------------------------------------------------------
WITH duplicatas AS (
    SELECT
        id_gestacao,
        COUNT(*) AS ocorrencias,
        STRING_AGG(CAST(id_paciente AS STRING), ', ') AS pacientes_duplicados
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
    GROUP BY id_gestacao
    HAVING COUNT(*) > 1
)
SELECT
    '2.1' AS modulo,
    'Duplicatas de id_gestacao' AS validacao,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS ✅'
        ELSE CONCAT('FAIL ❌ - ', CAST(COUNT(*) AS STRING), ' id_gestacao duplicados')
    END AS status,
    0 AS valor_esperado,
    CAST(COUNT(*) AS INT64) AS valor_atual,
    CASE
        WHEN COUNT(*) = 0 THEN 'Nenhuma duplicata encontrada'
        ELSE CONCAT('IDs duplicados: ', STRING_AGG(id_gestacao, ', ' LIMIT 5))
    END AS detalhes
FROM duplicatas;

-- Query de detalhes para duplicatas (executar se FAIL)
-- Descomente para investigar duplicatas:
/*
SELECT
    id_gestacao,
    id_paciente,
    cpf,
    nome,
    data_inicio,
    data_fim,
    fase_atual,
    data_snapshot
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = data_referencia
    AND id_gestacao IN (
        SELECT id_gestacao
        FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
        WHERE data_snapshot = data_referencia
        GROUP BY id_gestacao
        HAVING COUNT(*) > 1
    )
ORDER BY id_gestacao, id_paciente;
*/


-- ------------------------------------------------------------
-- Módulo 2.2: Datas Futuras
-- CRÍTICO: Zero datas futuras (data_fim ou data_inicio > data_referencia)
-- Threshold: 0 datas futuras permitidas
-- ------------------------------------------------------------
WITH datas_futuro AS (
    SELECT
        id_gestacao,
        data_inicio,
        data_fim,
        data_fim_efetiva,
        CASE
            WHEN data_inicio > data_referencia THEN 'data_inicio no futuro'
            WHEN data_fim > data_referencia THEN 'data_fim no futuro'
            WHEN data_fim_efetiva > data_referencia THEN 'data_fim_efetiva no futuro'
        END AS tipo_erro
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
        AND (
            data_inicio > data_referencia
            OR data_fim > data_referencia
            OR data_fim_efetiva > data_referencia
        )
)
SELECT
    '2.2' AS modulo,
    'Datas futuras' AS validacao,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS ✅'
        ELSE CONCAT('FAIL ❌ - ', CAST(COUNT(*) AS STRING), ' datas futuras encontradas')
    END AS status,
    0 AS valor_esperado,
    CAST(COUNT(*) AS INT64) AS valor_atual,
    CASE
        WHEN COUNT(*) = 0 THEN 'Nenhuma data futura encontrada'
        ELSE STRING_AGG(CONCAT(id_gestacao, ' (', tipo_erro, ')'), ', ' LIMIT 5)
    END AS detalhes
FROM datas_futuro;

-- Query de detalhes para datas futuras (executar se FAIL)
-- Descomente para investigar datas futuras:
/*
SELECT
    id_gestacao,
    id_paciente,
    nome,
    data_inicio,
    data_fim,
    data_fim_efetiva,
    dpp,
    fase_atual,
    data_referencia AS data_referencia_esperada
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = data_referencia
    AND (
        data_inicio > data_referencia
        OR data_fim > data_referencia
        OR data_fim_efetiva > data_referencia
    )
ORDER BY
    CASE
        WHEN data_inicio > data_referencia THEN data_inicio
        WHEN data_fim > data_referencia THEN data_fim
        ELSE data_fim_efetiva
    END DESC;
*/


-- ------------------------------------------------------------
-- Módulo 2.3: Inflação de Contagem
-- CRÍTICO: Contagem razoável (gestações ativas dentro do esperado)
-- Threshold: ≤ 10% variação = PASS, 10-20% = WARNING, > 20% = FAIL
-- ------------------------------------------------------------
WITH contagem_atual AS (
    SELECT
        COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
        COUNTIF(fase_atual = 'Puerpério') AS puerperas,
        COUNT(*) AS total_gestacoes
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
),
contagem_anterior AS (
    SELECT
        COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
        COUNTIF(fase_atual = 'Puerpério') AS puerperas,
        COUNT(*) AS total_gestacoes,
        MAX(data_snapshot) AS data_anterior
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = (
        SELECT MAX(data_snapshot)
        FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
        WHERE data_snapshot < data_referencia
    )
)
SELECT
    '2.3' AS modulo,
    'Inflação de contagem' AS validacao,
    CASE
        WHEN ca.gestacoes_ativas IS NULL THEN 'SKIP ⏭️ - Primeiro snapshot'
        WHEN ca.gestacoes_ativas = 0 THEN 'SKIP ⏭️ - Snapshot anterior sem gestações (baseline = 0)'
        WHEN ABS(c.gestacoes_ativas - ca.gestacoes_ativas) <= (ca.gestacoes_ativas * 0.10) THEN 'PASS ✅'
        WHEN ABS(c.gestacoes_ativas - ca.gestacoes_ativas) <= (ca.gestacoes_ativas * 0.20) THEN 'WARNING ⚠️'
        ELSE 'FAIL ❌'
    END AS status,
    CAST(ca.gestacoes_ativas AS INT64) AS valor_esperado,
    CAST(c.gestacoes_ativas AS INT64) AS valor_atual,
    CASE
        WHEN ca.gestacoes_ativas IS NULL THEN 'Primeiro snapshot - sem baseline para comparação'
        WHEN ca.gestacoes_ativas = 0 THEN CONCAT(
            'Snapshot anterior tinha 0 gestações | Atual: ',
            CAST(c.gestacoes_ativas AS STRING),
            ' gestações (crescimento absoluto)'
        )
        ELSE CONCAT(
            'Variação: ',
            CAST(ROUND(((c.gestacoes_ativas - ca.gestacoes_ativas) / ca.gestacoes_ativas) * 100, 2) AS STRING),
            '% | Anterior (',
            CAST(ca.data_anterior AS STRING),
            '): ',
            CAST(ca.gestacoes_ativas AS STRING),
            ' | Atual: ',
            CAST(c.gestacoes_ativas AS STRING)
        )
    END AS detalhes
FROM contagem_atual c
LEFT JOIN contagem_anterior ca ON 1=1;


-- ------------------------------------------------------------
-- Módulo 2.4: Classificação de Fases
-- CRÍTICO: Fases corretas (classificação consistente com datas)
-- Threshold: 0 classificações incorretas permitidas
-- ------------------------------------------------------------
WITH validacao_fase AS (
    SELECT
        id_gestacao,
        fase_atual,
        data_inicio,
        data_fim,
        data_fim_efetiva,
        -- Recalcular fase esperada com lógica exata do procedimento
        CASE
            -- Gestação: em curso na data_referencia
            WHEN data_inicio <= data_referencia
              AND (data_fim IS NULL OR data_fim >= data_referencia)
              AND DATE_ADD(data_inicio, INTERVAL 299 DAY) >= data_referencia
            THEN 'Gestação'

            -- Puerpério: até 42 dias após data_fim (INCLUSIVE)
            WHEN data_fim IS NOT NULL
              AND data_fim < data_referencia
              AND DATE_ADD(data_fim, INTERVAL 42 DAY) >= data_referencia
            THEN 'Puerpério'

            -- Encerrada: mais de 42 dias após data_fim
            WHEN data_fim IS NOT NULL
              AND DATE_ADD(data_fim, INTERVAL 42 DAY) < data_referencia
            THEN 'Encerrada'

            -- Gestação auto-encerrada (sem data_fim mas passou 299 dias)
            WHEN data_fim IS NULL
              AND DATE_ADD(data_inicio, INTERVAL 299 DAY) < data_referencia
            THEN 'Encerrada'

            ELSE 'Status indefinido'
        END AS fase_esperada
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
),
erros_classificacao AS (
    SELECT *
    FROM validacao_fase
    WHERE fase_atual != fase_esperada
)
SELECT
    '2.4' AS modulo,
    'Classificação de fases' AS validacao,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS ✅'
        ELSE CONCAT('FAIL ❌ - ', CAST(COUNT(*) AS STRING), ' fases incorretas')
    END AS status,
    0 AS valor_esperado,
    CAST(COUNT(*) AS INT64) AS valor_atual,
    CASE
        WHEN COUNT(*) = 0 THEN 'Todas as fases classificadas corretamente'
        ELSE STRING_AGG(
            CONCAT(id_gestacao, ': atual=', fase_atual, ' esperada=', fase_esperada),
            '; '
            LIMIT 3
        )
    END AS detalhes
FROM erros_classificacao;

-- Query de detalhes para fases incorretas (executar se FAIL)
-- Descomente para investigar fases incorretas:
/*
WITH validacao_fase AS (
    SELECT
        id_gestacao,
        id_paciente,
        nome,
        fase_atual,
        data_inicio,
        data_fim,
        data_fim_efetiva,
        ig_atual_semanas,
        CASE
            WHEN data_inicio <= data_referencia
              AND (data_fim IS NULL OR data_fim >= data_referencia)
              AND DATE_ADD(data_inicio, INTERVAL 299 DAY) >= data_referencia
            THEN 'Gestação'
            WHEN data_fim IS NOT NULL
              AND data_fim < data_referencia
              AND DATE_ADD(data_fim, INTERVAL 42 DAY) >= data_referencia
            THEN 'Puerpério'
            WHEN data_fim IS NOT NULL
              AND DATE_ADD(data_fim, INTERVAL 42 DAY) < data_referencia
            THEN 'Encerrada'
            WHEN data_fim IS NULL
              AND DATE_ADD(data_inicio, INTERVAL 299 DAY) < data_referencia
            THEN 'Encerrada'
            ELSE 'Status indefinido'
        END AS fase_esperada,
        DATE_ADD(data_inicio, INTERVAL 299 DAY) AS limite_299_dias,
        CASE WHEN data_fim IS NOT NULL THEN DATE_ADD(data_fim, INTERVAL 42 DAY) ELSE NULL END AS limite_puerperio
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
)
SELECT *
FROM validacao_fase
WHERE fase_atual != fase_esperada
ORDER BY id_gestacao;
*/


-- ============================================================
-- SEÇÃO 3: QUALIDADE DE DADOS
-- ============================================================
SELECT '3. QUALIDADE DE DADOS' AS secao, 'Validações de integridade e coerência' AS acao;

-- ------------------------------------------------------------
-- Módulo 3.1: Completude de Campos Críticos
-- Valida presença de valores em campos essenciais
-- ------------------------------------------------------------
SELECT
    '3.1' AS modulo,
    'Completude de campos' AS validacao,
    CASE
        WHEN COUNTIF(id_paciente IS NULL) = 0
         AND COUNTIF(data_inicio IS NULL) = 0
         AND COUNTIF(fase_atual IS NULL) = 0
        THEN 'PASS ✅'
        ELSE 'FAIL ❌'
    END AS status,
    0 AS valor_esperado,
    CAST(
        COUNTIF(id_paciente IS NULL) +
        COUNTIF(data_inicio IS NULL) +
        COUNTIF(fase_atual IS NULL)
        AS INT64
    ) AS valor_atual,
    CONCAT(
        'id_paciente NULL: ', CAST(COUNTIF(id_paciente IS NULL) AS STRING), ' | ',
        'data_inicio NULL: ', CAST(COUNTIF(data_inicio IS NULL) AS STRING), ' | ',
        'fase_atual NULL: ', CAST(COUNTIF(fase_atual IS NULL) AS STRING)
    ) AS detalhes
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = data_referencia;


-- ------------------------------------------------------------
-- Módulo 3.2: Integridade Referencial
-- Valida se id_paciente existe na tabela de cadastro
-- ------------------------------------------------------------
WITH pacientes_gestacao AS (
    SELECT DISTINCT id_paciente
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
),
pacientes_cadastro AS (
    SELECT DISTINCT dados.id_paciente
    FROM `rj-sms.saude_historico_clinico.paciente`
),
pacientes_orfaos AS (
    SELECT pg.id_paciente
    FROM pacientes_gestacao pg
    LEFT JOIN pacientes_cadastro pc ON pg.id_paciente = pc.id_paciente
    WHERE pc.id_paciente IS NULL
)
SELECT
    '3.2' AS modulo,
    'Integridade referencial' AS validacao,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS ✅'
        ELSE CONCAT('FAIL ❌ - ', CAST(COUNT(*) AS STRING), ' pacientes órfãos')
    END AS status,
    0 AS valor_esperado,
    CAST(COUNT(*) AS INT64) AS valor_atual,
    CASE
        WHEN COUNT(*) = 0 THEN 'Todos os id_paciente existem no cadastro'
        ELSE CONCAT('Pacientes sem cadastro: ', STRING_AGG(CAST(id_paciente AS STRING), ', ' LIMIT 5))
    END AS detalhes
FROM pacientes_orfaos;


-- ------------------------------------------------------------
-- Módulo 3.3: Coerência Temporal
-- Valida se data_inicio <= data_fim (quando ambas existem)
-- ------------------------------------------------------------
WITH incoerencias_temporais AS (
    SELECT
        id_gestacao,
        data_inicio,
        data_fim,
        DATE_DIFF(data_fim, data_inicio, DAY) AS dias_duracao
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
        AND data_fim IS NOT NULL
        AND data_inicio > data_fim
)
SELECT
    '3.3' AS modulo,
    'Coerência temporal (data_inicio <= data_fim)' AS validacao,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS ✅'
        ELSE CONCAT('FAIL ❌ - ', CAST(COUNT(*) AS STRING), ' incoerências temporais')
    END AS status,
    0 AS valor_esperado,
    CAST(COUNT(*) AS INT64) AS valor_atual,
    CASE
        WHEN COUNT(*) = 0 THEN 'Todas as datas são coerentes'
        ELSE STRING_AGG(
            CONCAT(id_gestacao, ' (início: ', CAST(data_inicio AS STRING), ', fim: ', CAST(data_fim AS STRING), ')'),
            ', '
            LIMIT 3
        )
    END AS detalhes
FROM incoerencias_temporais;


-- ------------------------------------------------------------
-- Módulo 3.4: Lógica Clínica - IG (Idade Gestacional)
-- Valida se IG está entre 0-44 semanas (limite fisiológico + margem)
-- ------------------------------------------------------------
WITH ig_invalidas AS (
    SELECT
        id_gestacao,
        ig_atual_semanas,
        ig_final_semanas,
        fase_atual
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
        AND (
            (ig_atual_semanas IS NOT NULL AND (ig_atual_semanas < 0 OR ig_atual_semanas > 44))
            OR (ig_final_semanas IS NOT NULL AND (ig_final_semanas < 0 OR ig_final_semanas > 44))
        )
)
SELECT
    '3.4' AS modulo,
    'Lógica clínica - IG válida (0-44 semanas)' AS validacao,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS ✅'
        WHEN COUNT(*) <= 5 THEN 'WARNING ⚠️'
        ELSE 'FAIL ❌'
    END AS status,
    0 AS valor_esperado,
    CAST(COUNT(*) AS INT64) AS valor_atual,
    CASE
        WHEN COUNT(*) = 0 THEN 'Todas as IGs estão dentro do intervalo esperado'
        ELSE CONCAT(
            'IGs fora do intervalo: ',
            STRING_AGG(
                CONCAT(
                    id_gestacao,
                    ' (IG atual: ', CAST(ig_atual_semanas AS STRING),
                    ', IG final: ', CAST(IFNULL(ig_final_semanas, -1) AS STRING), ')'
                ),
                ', '
                LIMIT 3
            )
        )
    END AS detalhes
FROM ig_invalidas;


-- ------------------------------------------------------------
-- Módulo 3.5: Anomalias Estatísticas
-- Valida distribuição de fases está dentro do esperado
-- Esperado: Gestação (60-80%), Puerpério (5-15%), Encerrada (10-30%)
-- ------------------------------------------------------------
WITH distribuicao_fases AS (
    SELECT
        fase_atual,
        COUNT(*) AS quantidade,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentual
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
    GROUP BY fase_atual
)
SELECT
    '3.5' AS modulo,
    'Distribuição de fases' AS validacao,
    CASE
        WHEN MAX(CASE WHEN fase_atual = 'Gestação' AND (percentual < 50 OR percentual > 90) THEN 1 ELSE 0 END) = 1
        THEN 'WARNING ⚠️ - Distribuição atípica'
        ELSE 'PASS ✅'
    END AS status,
    CAST(NULL AS INT64) AS valor_esperado,
    CAST(NULL AS INT64) AS valor_atual,
    STRING_AGG(
        CONCAT(fase_atual, ': ', CAST(quantidade AS STRING), ' (', CAST(percentual AS STRING), '%)'),
        ' | '
    ) AS detalhes
FROM distribuicao_fases;


-- ============================================================
-- SEÇÃO 4: LÓGICA DE NEGÓCIO
-- ============================================================
SELECT '4. LÓGICA DE NEGÓCIO' AS secao, 'Validações de regras de negócio específicas' AS acao;

-- ------------------------------------------------------------
-- Módulo 4.1: Cálculo DUM Razoável (Janela 340 dias)
-- Valida se data_inicio está dentro da janela esperada
-- Janela: 340 dias = 299 dias (gestação) + 42 dias (puerpério) - 1 dia
-- ------------------------------------------------------------
WITH dum_fora_janela AS (
    SELECT
        id_gestacao,
        data_inicio,
        DATE_DIFF(data_referencia, data_inicio, DAY) AS dias_desde_inicio,
        fase_atual
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
        AND DATE_DIFF(data_referencia, data_inicio, DAY) > 340
        AND fase_atual IN ('Gestação', 'Puerpério')
)
SELECT
    '4.1' AS modulo,
    'DUM dentro da janela 340 dias' AS validacao,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS ✅'
        ELSE CONCAT('FAIL ❌ - ', CAST(COUNT(*) AS STRING), ' gestações fora da janela')
    END AS status,
    0 AS valor_esperado,
    CAST(COUNT(*) AS INT64) AS valor_atual,
    CASE
        WHEN COUNT(*) = 0 THEN 'Todas as data_inicio estão dentro da janela esperada'
        ELSE STRING_AGG(
            CONCAT(id_gestacao, ' (', CAST(dias_desde_inicio AS STRING), ' dias, fase: ', fase_atual, ')'),
            ', '
            LIMIT 3
        )
    END AS detalhes
FROM dum_fora_janela;


-- ------------------------------------------------------------
-- Módulo 4.2: Janela 60 dias (Separação de Gestações)
-- Valida se não há gestações muito próximas para mesma paciente
-- Threshold: WARNING se < 60 dias entre gestações
-- ------------------------------------------------------------
WITH gestacoes_ordenadas AS (
    SELECT
        id_paciente,
        id_gestacao,
        data_inicio,
        numero_gestacao,
        LAG(data_inicio) OVER (PARTITION BY id_paciente ORDER BY data_inicio) AS data_inicio_anterior
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
),
gestacoes_proximas AS (
    SELECT
        id_paciente,
        id_gestacao,
        data_inicio,
        data_inicio_anterior,
        DATE_DIFF(data_inicio, data_inicio_anterior, DAY) AS dias_entre_gestacoes
    FROM gestacoes_ordenadas
    WHERE data_inicio_anterior IS NOT NULL
        AND DATE_DIFF(data_inicio, data_inicio_anterior, DAY) < 60
)
SELECT
    '4.2' AS modulo,
    'Separação 60 dias entre gestações' AS validacao,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS ✅'
        WHEN COUNT(*) <= 10 THEN 'WARNING ⚠️'
        ELSE 'FAIL ❌'
    END AS status,
    0 AS valor_esperado,
    CAST(COUNT(*) AS INT64) AS valor_atual,
    CASE
        WHEN COUNT(*) = 0 THEN 'Todas as gestações estão adequadamente separadas'
        ELSE CONCAT(
            'Gestações com intervalo < 60 dias: ',
            STRING_AGG(
                CONCAT(
                    CAST(id_paciente AS STRING),
                    ' (', CAST(dias_entre_gestacoes AS STRING), ' dias)'
                ),
                ', '
                LIMIT 3
            )
        )
    END AS detalhes
FROM gestacoes_proximas;


-- ------------------------------------------------------------
-- Módulo 4.3: Auto-encerramento (Regra 299 dias)
-- Valida se gestações sem data_fim são auto-encerradas após 299 dias
-- ------------------------------------------------------------
WITH auto_encerramento_incorreto AS (
    SELECT
        id_gestacao,
        data_inicio,
        data_fim,
        data_fim_efetiva,
        fase_atual,
        DATE_DIFF(data_referencia, data_inicio, DAY) AS dias_desde_inicio
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
        AND data_fim IS NULL
        AND DATE_DIFF(data_referencia, data_inicio, DAY) > 299
        AND (
            -- Deveria estar Encerrada mas não está
            (fase_atual != 'Encerrada')
            OR
            -- data_fim_efetiva deveria ser data_inicio + 299 dias
            (data_fim_efetiva != DATE_ADD(data_inicio, INTERVAL 299 DAY))
        )
)
SELECT
    '4.3' AS modulo,
    'Auto-encerramento 299 dias' AS validacao,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS ✅'
        ELSE CONCAT('FAIL ❌ - ', CAST(COUNT(*) AS STRING), ' auto-encerramentos incorretos')
    END AS status,
    0 AS valor_esperado,
    CAST(COUNT(*) AS INT64) AS valor_atual,
    CASE
        WHEN COUNT(*) = 0 THEN 'Auto-encerramento aplicado corretamente'
        ELSE STRING_AGG(
            CONCAT(
                id_gestacao,
                ' (', CAST(dias_desde_inicio AS STRING), ' dias, fase: ', fase_atual, ')'
            ),
            ', '
            LIMIT 3
        )
    END AS detalhes
FROM auto_encerramento_incorreto;


-- ------------------------------------------------------------
-- Módulo 4.4: Transições de Fase (Limites 42 dias puerpério)
-- Valida se transição Puerpério → Encerrada ocorre aos 42 dias
-- ------------------------------------------------------------
WITH transicoes_incorretas AS (
    SELECT
        id_gestacao,
        data_fim,
        fase_atual,
        DATE_DIFF(data_referencia, data_fim, DAY) AS dias_desde_fim
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_referencia
        AND data_fim IS NOT NULL
        AND (
            -- Deveria estar em Puerpério mas está em outra fase
            (DATE_DIFF(data_referencia, data_fim, DAY) BETWEEN 0 AND 42 AND fase_atual != 'Puerpério')
            OR
            -- Deveria estar Encerrada mas está em Puerpério
            (DATE_DIFF(data_referencia, data_fim, DAY) > 42 AND fase_atual = 'Puerpério')
        )
)
SELECT
    '4.4' AS modulo,
    'Transição puerpério (42 dias)' AS validacao,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS ✅'
        ELSE CONCAT('FAIL ❌ - ', CAST(COUNT(*) AS STRING), ' transições incorretas')
    END AS status,
    0 AS valor_esperado,
    CAST(COUNT(*) AS INT64) AS valor_atual,
    CASE
        WHEN COUNT(*) = 0 THEN 'Transições de puerpério corretas'
        ELSE STRING_AGG(
            CONCAT(
                id_gestacao,
                ' (', CAST(dias_desde_fim AS STRING), ' dias pós-parto, fase: ', fase_atual, ')'
            ),
            ', '
            LIMIT 3
        )
    END AS detalhes
FROM transicoes_incorretas;


-- ============================================================
-- SEÇÃO 5: RESUMO CONSOLIDADO
-- ============================================================
SELECT '5. RESUMO CONSOLIDADO' AS secao, 'Visão geral dos resultados' AS acao;

-- ------------------------------------------------------------
-- Contadores Gerais
-- ------------------------------------------------------------
SELECT
    'Resumo Geral' AS categoria,
    COUNT(*) AS total_gestacoes,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(fase_atual = 'Puerpério') AS puerperas,
    COUNTIF(fase_atual = 'Encerrada') AS gestacoes_encerradas,
    COUNT(DISTINCT id_paciente) AS pacientes_unicos,
    ROUND(AVG(ig_atual_semanas), 1) AS ig_media_semanas,
    ROUND(AVG(idade_gestante), 1) AS idade_media_anos,
    data_referencia AS data_validacao
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = data_referencia;


-- ============================================================
-- RELATÓRIO FINAL
-- ============================================================
SELECT
    '═══════════════════════════════════════════════════════════' AS separador
UNION ALL
SELECT
    '  VALIDAÇÃO CONCLUÍDA - Procedimento 1: Gestações Histórico'
UNION ALL
SELECT
    CONCAT('  Data de referência: ', CAST(data_referencia AS STRING))
UNION ALL
SELECT
    CONCAT('  Data de execução: ', CAST(CURRENT_TIMESTAMP() AS STRING))
UNION ALL
SELECT
    '═══════════════════════════════════════════════════════════'
UNION ALL
SELECT
    ''
UNION ALL
SELECT
    '📋 INSTRUÇÕES:'
UNION ALL
SELECT
    '  1. Revise cada módulo de validação acima'
UNION ALL
SELECT
    '  2. Investigue qualquer FAIL ❌ usando as queries de detalhes'
UNION ALL
SELECT
    '  3. Considere WARNING ⚠️ como alertas que requerem atenção'
UNION ALL
SELECT
    '  4. PASS ✅ indica validação bem-sucedida'
UNION ALL
SELECT
    '  5. SKIP ⏭️ indica validação não aplicável (ex: primeiro snapshot)'
UNION ALL
SELECT
    ''
UNION ALL
SELECT
    '🎯 CRITÉRIOS DE APROVAÇÃO:'
UNION ALL
SELECT
    '  ✅ APROVAÇÃO COMPLETA: Todos os módulos críticos (2.1-2.4) = PASS'
UNION ALL
SELECT
    '  ⚠️ APROVAÇÃO CONDICIONAL: ≤2 WARNING em módulos não-críticos'
UNION ALL
SELECT
    '  ❌ REPROVAÇÃO: Qualquer FAIL em módulos críticos (2.1-2.4)'
UNION ALL
SELECT
    ''
UNION ALL
SELECT
    '═══════════════════════════════════════════════════════════';
