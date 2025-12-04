-- ============================================================
-- INVESTIGAÇÃO: Por que temos gestações demais?
-- ============================================================
-- Objetivo: Entender se a janela de 60 dias está funcionando corretamente
-- Data: 03/12/2025
-- ============================================================

DECLARE data_referencia DATE DEFAULT DATE('2025-07-01');

WITH

    -- Cadastro de pacientes
    cadastro_paciente AS (
        SELECT
            dados.id_paciente,
            dados.nome,
            DATE_DIFF (
                data_referencia,
                dados.data_nascimento,
                YEAR
            ) AS idade_gestante
        FROM `rj-sms.saude_historico_clinico.paciente`
    ),

    -- Eventos brutos
    eventos_brutos AS (
        SELECT
            id_hci,
            paciente.id_paciente AS id_paciente,
            paciente_cpf as cpf,
            cp.nome,
            c.id AS cid,
            c.situacao AS situacao_cid,
            SAFE.PARSE_DATE (
                '%Y-%m-%d',
                SUBSTR(c.data_diagnostico, 1, 10)
            ) AS data_evento
        FROM
            `rj-sms.saude_historico_clinico.episodio_assistencial`
            LEFT JOIN UNNEST (condicoes) c
            INNER JOIN cadastro_paciente cp ON paciente.id_paciente = cp.id_paciente
        WHERE
            c.data_diagnostico IS NOT NULL
            AND c.data_diagnostico != ''
            AND c.situacao IN ('ATIVO', 'RESOLVIDO')
            AND (
                c.id = 'Z321'
                OR c.id LIKE 'Z34%'
                OR c.id LIKE 'Z35%'
            )
            AND paciente.id_paciente IS NOT NULL
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) <= data_referencia
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
    ),

    -- Agrupamento temporal
    eventos_com_periodo AS (
        SELECT
            *,
            LAG(data_evento) OVER (
                PARTITION BY id_paciente
                ORDER BY data_evento
            ) AS data_evento_anterior,
            CASE
                WHEN LAG(data_evento) OVER (
                    PARTITION BY id_paciente
                    ORDER BY data_evento
                ) IS NULL THEN 1
                WHEN DATE_DIFF(
                    data_evento,
                    LAG(data_evento) OVER (
                        PARTITION BY id_paciente
                        ORDER BY data_evento
                    ),
                    DAY
                ) > 60 THEN 1
                ELSE 0
            END AS nova_gestacao_flag,
            DATE_DIFF(
                data_evento,
                LAG(data_evento) OVER (
                    PARTITION BY id_paciente
                    ORDER BY data_evento
                ),
                DAY
            ) AS dias_desde_anterior
        FROM eventos_brutos
    ),

    eventos_com_grupo AS (
        SELECT
            *,
            SUM(nova_gestacao_flag) OVER (
                PARTITION BY id_paciente
                ORDER BY data_evento
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS grupo_gestacao
        FROM eventos_com_periodo
    ),

    -- Casos onde id_hci se repete
    id_hci_duplicados AS (
        SELECT
            id_hci,
            COUNT(DISTINCT grupo_gestacao) AS grupos_distintos,
            STRING_AGG(CAST(grupo_gestacao AS STRING) ORDER BY grupo_gestacao) AS grupos,
            COUNT(*) AS total_eventos
        FROM eventos_com_grupo
        GROUP BY id_hci
        HAVING COUNT(DISTINCT grupo_gestacao) > 1
    )

-- ============================================================
-- ANÁLISES
-- ============================================================

SELECT
    '=== ANÁLISE 1: Distribuição de diferenças temporais ===' AS analise,
    NULL AS metrica,
    NULL AS valor

UNION ALL

SELECT
    '',
    'Eventos com diferença ≤ 7 dias',
    COUNT(*)
FROM eventos_com_periodo
WHERE dias_desde_anterior IS NOT NULL AND dias_desde_anterior <= 7

UNION ALL

SELECT
    '',
    'Eventos com diferença 8-30 dias',
    COUNT(*)
FROM eventos_com_periodo
WHERE dias_desde_anterior BETWEEN 8 AND 30

UNION ALL

SELECT
    '',
    'Eventos com diferença 31-60 dias',
    COUNT(*)
FROM eventos_com_periodo
WHERE dias_desde_anterior BETWEEN 31 AND 60

UNION ALL

SELECT
    '',
    'Eventos com diferença 61-90 dias',
    COUNT(*)
FROM eventos_com_periodo
WHERE dias_desde_anterior BETWEEN 61 AND 90

UNION ALL

SELECT
    '',
    'Eventos com diferença > 90 dias',
    COUNT(*)
FROM eventos_com_periodo
WHERE dias_desde_anterior > 90

UNION ALL

SELECT
    '',
    NULL,
    NULL

UNION ALL

SELECT
    '=== ANÁLISE 2: id_hci em múltiplos grupos ===',
    NULL,
    NULL

UNION ALL

SELECT
    '',
    'Total de id_hci únicos',
    COUNT(DISTINCT id_hci)
FROM eventos_com_grupo

UNION ALL

SELECT
    '',
    'id_hci que aparecem em 2+ grupos',
    COUNT(*)
FROM id_hci_duplicados

UNION ALL

SELECT
    '',
    'Eventos afetados por id_hci duplicados',
    SUM(total_eventos)
FROM id_hci_duplicados

UNION ALL

SELECT
    '',
    NULL,
    NULL

UNION ALL

SELECT
    '=== ANÁLISE 3: Pacientes com múltiplas gestações ===',
    NULL,
    NULL

UNION ALL

SELECT
    '',
    'Pacientes com 2 gestações',
    COUNTIF(total_grupos = 2)
FROM (
    SELECT id_paciente, COUNT(DISTINCT grupo_gestacao) AS total_grupos
    FROM eventos_com_grupo
    GROUP BY id_paciente
)

UNION ALL

SELECT
    '',
    'Pacientes com 3+ gestações',
    COUNTIF(total_grupos >= 3)
FROM (
    SELECT id_paciente, COUNT(DISTINCT grupo_gestacao) AS total_grupos
    FROM eventos_com_grupo
    GROUP BY id_paciente
)

UNION ALL

SELECT
    '',
    'Máximo de gestações por paciente',
    MAX(total_grupos)
FROM (
    SELECT id_paciente, COUNT(DISTINCT grupo_gestacao) AS total_grupos
    FROM eventos_com_grupo
    GROUP BY id_paciente
)

ORDER BY analise, metrica;
