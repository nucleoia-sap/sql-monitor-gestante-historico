-- ============================================================
-- TESTE DE DUPLICAÇÕES: Lógica de MODA com Agrupamento Temporal
-- ============================================================
-- Objetivo: Verificar se há duplicações na lógica de MODA
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

    -- Eventos brutos de gestação (ATIVO e RESOLVIDO)
    eventos_brutos AS (
        SELECT
            id_hci,
            paciente.id_paciente AS id_paciente,
            paciente_cpf as cpf,
            cp.nome,
            cp.idade_gestante,
            c.id AS cid,
            c.situacao AS situacao_cid,
            SAFE.PARSE_DATE (
                '%Y-%m-%d',
                SUBSTR(c.data_diagnostico, 1, 10)
            ) AS data_evento,
            CASE
                WHEN c.id = 'Z321'
                OR c.id LIKE 'Z34%'
                OR c.id LIKE 'Z35%' THEN 'gestacao'
                ELSE NULL
            END AS tipo_evento
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

    -- Filtrar apenas eventos de gestação
    eventos_gestacao AS (
        SELECT *
        FROM eventos_brutos
        WHERE tipo_evento = 'gestacao'
    ),

    -- Agrupar eventos em períodos de gestação (janela de 60 dias)
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
            END AS nova_gestacao_flag
        FROM eventos_gestacao
    ),

    -- Criar ID de período de gestação
    eventos_com_grupo_gestacao AS (
        SELECT
            *,
            SUM(nova_gestacao_flag) OVER (
                PARTITION BY id_paciente
                ORDER BY data_evento
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS grupo_gestacao
        FROM eventos_com_periodo
    ),

    -- Calcular frequência de cada data_evento DENTRO de cada grupo de gestação
    frequencia_datas AS (
        SELECT
            id_paciente,
            grupo_gestacao,
            data_evento,
            COUNT(*) AS frequencia,
            ANY_VALUE(id_hci) AS id_hci,
            ANY_VALUE(cpf) AS cpf,
            ANY_VALUE(nome) AS nome,
            ANY_VALUE(idade_gestante) AS idade_gestante
        FROM eventos_com_grupo_gestacao
        GROUP BY id_paciente, grupo_gestacao, data_evento
    ),

    -- Selecionar MODA (data com maior frequência) DENTRO de cada grupo
    moda_por_grupo_gestacao AS (
        SELECT
            id_paciente,
            grupo_gestacao,
            data_evento AS dum_estimada,
            frequencia,
            id_hci,
            cpf,
            nome,
            idade_gestante,
            ROW_NUMBER() OVER (
                PARTITION BY id_paciente, grupo_gestacao
                ORDER BY frequencia DESC, data_evento DESC
            ) AS rn
        FROM frequencia_datas
    ),

    -- Selecionar apenas a MODA de cada grupo (rn = 1)
    inicios_por_moda AS (
        SELECT
            id_hci,
            id_paciente,
            cpf,
            nome,
            idade_gestante,
            grupo_gestacao,
            dum_estimada AS data_evento,
            frequencia AS vezes_registrada
        FROM moda_por_grupo_gestacao
        WHERE rn = 1
    )

-- ============================================================
-- ANÁLISES DE DUPLICAÇÃO
-- ============================================================

SELECT
    '=== TESTE 1: Duplicações por (id_paciente, data_evento) ===' AS teste,
    NULL AS total,
    NULL AS duplicacoes,
    NULL AS percentual

UNION ALL

SELECT
    'Total de registros em inicios_por_moda',
    COUNT(*),
    NULL,
    NULL
FROM inicios_por_moda

UNION ALL

SELECT
    'Registros únicos por (id_paciente, data_evento)',
    COUNT(DISTINCT CONCAT(id_paciente, '|', CAST(data_evento AS STRING))),
    NULL,
    NULL
FROM inicios_por_moda

UNION ALL

SELECT
    'Casos de duplicação',
    NULL,
    SUM(ocorrencias - 1),
    NULL
FROM (
    SELECT
        id_paciente,
        data_evento,
        COUNT(*) AS ocorrencias
    FROM inicios_por_moda
    GROUP BY id_paciente, data_evento
    HAVING COUNT(*) > 1
)

UNION ALL

SELECT
    '',
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    '=== TESTE 2: Duplicações por (id_paciente, grupo_gestacao) ===',
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    'Registros únicos por (id_paciente, grupo_gestacao)',
    COUNT(DISTINCT CONCAT(id_paciente, '|', CAST(grupo_gestacao AS STRING))),
    NULL,
    NULL
FROM inicios_por_moda

UNION ALL

SELECT
    'Casos de duplicação por grupo',
    NULL,
    SUM(ocorrencias - 1),
    NULL
FROM (
    SELECT
        id_paciente,
        grupo_gestacao,
        COUNT(*) AS ocorrencias
    FROM inicios_por_moda
    GROUP BY id_paciente, grupo_gestacao
    HAVING COUNT(*) > 1
)

UNION ALL

SELECT
    '',
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    '=== TESTE 3: Gestações múltiplas (esperado) ===',
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    'Pacientes únicos',
    COUNT(DISTINCT id_paciente),
    NULL,
    NULL
FROM inicios_por_moda

UNION ALL

SELECT
    'Total de gestações',
    COUNT(*),
    NULL,
    NULL
FROM inicios_por_moda

UNION ALL

SELECT
    'Pacientes com 2+ gestações',
    COUNT(*),
    NULL,
    CONCAT(CAST(ROUND(COUNT(*) * 100.0 / (SELECT COUNT(DISTINCT id_paciente) FROM inicios_por_moda), 2) AS STRING), '%')
FROM (
    SELECT
        id_paciente,
        COUNT(*) AS total_gestacoes
    FROM inicios_por_moda
    GROUP BY id_paciente
    HAVING COUNT(*) >= 2
)

UNION ALL

SELECT
    '',
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    '=== TESTE 4: Análise de id_hci ===',
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    'Total de id_hci únicos',
    COUNT(DISTINCT id_hci),
    NULL,
    NULL
FROM inicios_por_moda

UNION ALL

SELECT
    'Casos onde mesmo id_hci aparece em múltiplas gestações',
    NULL,
    SUM(ocorrencias - 1),
    NULL
FROM (
    SELECT
        id_hci,
        COUNT(*) AS ocorrencias
    FROM inicios_por_moda
    GROUP BY id_hci
    HAVING COUNT(*) > 1
)

ORDER BY teste;
