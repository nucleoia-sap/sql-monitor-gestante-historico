-- Análise dos resultados da query_teste_gestacoes.sql
-- Data de referência: 2025-01-01

WITH dados_teste AS (
    DECLARE data_referencia DATE DEFAULT DATE('2025-01-01');

    WITH
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

        eventos_desfecho AS (
            SELECT
                paciente.id_paciente AS id_paciente,
                SAFE.PARSE_DATE (
                    '%Y-%m-%d',
                    SUBSTR(c.data_diagnostico, 1, 10)
                ) AS data_desfecho,
                c.id AS cid_desfecho,
                CASE
                    WHEN c.id BETWEEN 'O00' AND 'O08' THEN 'aborto'
                    WHEN c.id BETWEEN 'O80' AND 'O84' THEN 'parto'
                    WHEN c.id BETWEEN 'O85' AND 'O92' THEN 'puerperio_confirmado'
                    ELSE 'outro_desfecho'
                END AS tipo_desfecho
            FROM
                `rj-sms.saude_historico_clinico.episodio_assistencial`
                LEFT JOIN UNNEST (condicoes) c
            WHERE
                c.data_diagnostico IS NOT NULL
                AND c.data_diagnostico != ''
                AND paciente.id_paciente IS NOT NULL
                AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) <= data_referencia
                AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) >= DATE_SUB(data_referencia, INTERVAL 365 DAY)
                AND (c.id BETWEEN 'O00' AND 'O99')
        ),

        primeiro_desfecho AS (
            SELECT
                i.id_hci,
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
            GROUP BY i.id_hci, i.id_paciente, i.data_evento
        ),

        gestacoes_unicas AS (
            SELECT
                pd.id_hci,
                pd.id_paciente,
                eb.cpf,
                eb.nome,
                eb.idade_gestante,
                pd.data_inicio,
                pd.data_fim,
                pd.tipo_desfecho,
                pd.cid_desfecho,
                ROW_NUMBER() OVER (
                    PARTITION BY pd.id_paciente
                    ORDER BY pd.data_inicio
                ) AS numero_gestacao,
                CONCAT(
                    pd.id_paciente,
                    '-',
                    CAST(
                        ROW_NUMBER() OVER (
                            PARTITION BY pd.id_paciente
                            ORDER BY pd.data_inicio
                        ) AS STRING
                    )
                ) AS id_gestacao
            FROM primeiro_desfecho pd
            INNER JOIN eventos_brutos eb
                ON pd.id_hci = eb.id_hci
                AND pd.id_paciente = eb.id_paciente
                AND pd.data_inicio = eb.data_evento
        ),

        gestacoes_com_status AS (
            SELECT
                *,
                CASE
                    WHEN data_fim IS NOT NULL THEN data_fim
                    WHEN DATE_ADD(data_inicio, INTERVAL 299 DAY) <= data_referencia
                    THEN DATE_ADD(data_inicio, INTERVAL 299 DAY)
                    ELSE NULL
                END AS data_fim_efetiva,
                DATE_ADD(data_inicio, INTERVAL 40 WEEK) AS dpp
            FROM gestacoes_unicas
        ),

        gestacoes_com_fase AS (
            SELECT
                gcs.*,
                CASE
                    WHEN gcs.data_inicio <= data_referencia
                    AND (
                        gcs.data_fim IS NULL OR gcs.data_fim >= data_referencia
                    )
                    AND DATE_ADD(gcs.data_inicio, INTERVAL 299 DAY) >= data_referencia
                    THEN 'Gestação'

                    WHEN gcs.data_fim IS NOT NULL
                    AND gcs.data_fim < data_referencia
                    AND DATE_ADD(gcs.data_fim, INTERVAL 42 DAY) >= data_referencia
                    THEN 'Puerpério'

                    WHEN gcs.data_fim IS NOT NULL
                    AND DATE_ADD(gcs.data_fim, INTERVAL 42 DAY) < data_referencia
                    THEN 'Encerrada'

                    WHEN gcs.data_fim IS NULL
                    AND DATE_ADD(gcs.data_inicio, INTERVAL 299 DAY) < data_referencia
                    THEN 'Encerrada'

                    ELSE 'Status indefinido'
                END AS fase_atual,

                CASE
                    WHEN DATE_DIFF(data_referencia, gcs.data_inicio, WEEK) <= 13 THEN '1º trimestre'
                    WHEN DATE_DIFF(data_referencia, gcs.data_inicio, WEEK) BETWEEN 14 AND 27 THEN '2º trimestre'
                    WHEN DATE_DIFF(data_referencia, gcs.data_inicio, WEEK) >= 28 THEN '3º trimestre'
                    ELSE 'Não aplicável'
                END AS trimestre_atual_gestacao,

                DATE_DIFF(data_referencia, gcs.data_inicio, WEEK) AS ig_atual_semanas,

                CASE
                    WHEN gcs.data_fim IS NOT NULL
                    THEN DATE_DIFF(gcs.data_fim, gcs.data_inicio, WEEK)
                    ELSE NULL
                END AS ig_final_semanas
            FROM gestacoes_com_status gcs
        ),

        filtrado AS (
            SELECT *
            FROM gestacoes_com_fase
            WHERE fase_atual IN ('Gestação', 'Puerpério')
        )

    SELECT * FROM filtrado
)

-- ANÁLISE ESTATÍSTICA
SELECT
    '=== RESUMO GERAL ===' AS metrica,
    CAST(NULL AS INT64) AS valor_numerico,
    CAST(NULL AS STRING) AS valor_texto,
    CAST(NULL AS DATE) AS valor_data

UNION ALL

SELECT
    'Total de registros',
    COUNT(*),
    CAST(COUNT(*) AS STRING),
    NULL
FROM dados_teste

UNION ALL

SELECT
    'Pacientes únicos',
    COUNT(DISTINCT id_paciente),
    CAST(COUNT(DISTINCT id_paciente) AS STRING),
    NULL
FROM dados_teste

UNION ALL

SELECT
    'Gestações únicas',
    COUNT(DISTINCT id_gestacao),
    CAST(COUNT(DISTINCT id_gestacao) AS STRING),
    NULL
FROM dados_teste

UNION ALL

SELECT
    '',
    NULL,
    '',
    NULL

UNION ALL

SELECT
    '=== DISTRIBUIÇÃO POR FASE ===',
    NULL,
    '',
    NULL

UNION ALL

SELECT
    fase_atual,
    COUNT(*),
    CONCAT(CAST(COUNT(*) AS STRING), ' (', CAST(ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS STRING), '%)'),
    NULL
FROM dados_teste
GROUP BY fase_atual

UNION ALL

SELECT
    '',
    NULL,
    '',
    NULL

UNION ALL

SELECT
    '=== DATAS DE INÍCIO ===',
    NULL,
    '',
    NULL

UNION ALL

SELECT
    'Data mínima',
    NULL,
    '',
    MIN(data_inicio)
FROM dados_teste

UNION ALL

SELECT
    'Data máxima',
    NULL,
    '',
    MAX(data_inicio)
FROM dados_teste

UNION ALL

SELECT
    'Range (dias)',
    DATE_DIFF(MAX(data_inicio), MIN(data_inicio), DAY),
    CAST(DATE_DIFF(MAX(data_inicio), MIN(data_inicio), DAY) AS STRING),
    NULL
FROM dados_teste

UNION ALL

SELECT
    '',
    NULL,
    '',
    NULL

UNION ALL

SELECT
    '=== IDADE GESTACIONAL (GESTAÇÕES ATIVAS) ===',
    NULL,
    '',
    NULL

UNION ALL

SELECT
    'IG Média (semanas)',
    CAST(ROUND(AVG(ig_atual_semanas), 2) AS INT64),
    CAST(ROUND(AVG(ig_atual_semanas), 2) AS STRING),
    NULL
FROM dados_teste
WHERE fase_atual = 'Gestação'

UNION ALL

SELECT
    'IG Mínima (semanas)',
    MIN(ig_atual_semanas),
    CAST(MIN(ig_atual_semanas) AS STRING),
    NULL
FROM dados_teste
WHERE fase_atual = 'Gestação'

UNION ALL

SELECT
    'IG Máxima (semanas)',
    MAX(ig_atual_semanas),
    CAST(MAX(ig_atual_semanas) AS STRING),
    NULL
FROM dados_teste
WHERE fase_atual = 'Gestação'

ORDER BY metrica;
