-- ============================================================
-- VALIDAÇÃO DA LÓGICA DE DEDUPLICAÇÃO APRIMORADA
-- ============================================================
--
-- Este script valida se a correção de deduplicação está funcionando
-- comparando os casos problemáticos identificados antes e depois
--
-- Data de referência: 2025-07-01 (mesma da query de teste)
-- ============================================================

WITH resultado_corrigido AS (
    -- Executar a query corrigida completa
    DECLARE data_referencia DATE DEFAULT DATE('2025-07-01');

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

        inicios_brutos AS (
            SELECT *
            FROM eventos_brutos
            WHERE
                tipo_evento = 'gestacao'
                AND situacao_cid = 'ATIVO'
        ),

        inicios_com_grupo AS (
            SELECT
                *,
                LAG(data_evento) OVER (
                    PARTITION BY id_paciente
                    ORDER BY data_evento
                ) AS data_anterior,
                CASE
                    WHEN LAG(data_evento) OVER (
                        PARTITION BY id_paciente
                        ORDER BY data_evento
                    ) IS NULL THEN 1
                    WHEN DATE_DIFF (
                        data_evento,
                        LAG(data_evento) OVER (
                            PARTITION BY id_paciente
                            ORDER BY data_evento
                        ),
                        DAY
                    ) >= 60 THEN 1
                    ELSE 0
                END AS nova_ocorrencia_flag
            FROM inicios_brutos
        ),

        grupos_inicios AS (
            SELECT *, SUM(nova_ocorrencia_flag) OVER (
                    PARTITION BY id_paciente
                    ORDER BY data_evento
                ) AS grupo_id
            FROM inicios_com_grupo
        ),

        inicios_deduplicados AS (
            SELECT *
            FROM (
                    SELECT *, ROW_NUMBER() OVER (
                            PARTITION BY id_paciente, grupo_id
                            ORDER BY data_evento DESC
                        ) AS rn
                    FROM grupos_inicios
                )
            WHERE rn = 1
        ),

        primeiro_desfecho AS (
            SELECT
                ARRAY_AGG(i.id_hci ORDER BY i.data_evento LIMIT 1)[OFFSET(0)] AS id_hci,
                i.id_paciente,
                i.data_evento AS data_inicio,
                MIN(d.data_desfecho) AS data_fim,
                ARRAY_AGG(d.tipo_desfecho ORDER BY d.data_desfecho LIMIT 1)[OFFSET(0)] AS tipo_desfecho,
                ARRAY_AGG(d.cid_desfecho ORDER BY d.data_desfecho LIMIT 1)[OFFSET(0)] AS cid_desfecho
            FROM inicios_deduplicados i
            LEFT JOIN eventos_desfecho d
                ON i.id_paciente = d.id_paciente
                AND d.data_desfecho > i.data_evento
                AND DATE_DIFF(d.data_desfecho, i.data_evento, DAY) <= 320
            WHERE i.data_evento <= data_referencia
                AND i.tipo_evento = 'gestacao'
            GROUP BY i.id_paciente, i.data_evento
        ),

        gestacoes_unicas AS (
            SELECT
                pd.id_hci,
                pd.id_paciente,
                id.cpf,
                id.nome,
                id.idade_gestante,
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
            INNER JOIN inicios_deduplicados id
                ON pd.id_hci = id.id_hci
                AND pd.id_paciente = id.id_paciente
                AND pd.data_inicio = id.data_evento
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
        )

    SELECT * FROM gestacoes_com_fase
    WHERE fase_atual IN ('Gestação', 'Puerpério')
)

-- ============================================================
-- VALIDAÇÃO DOS CASOS PROBLEMÁTICOS
-- ============================================================

SELECT
    '=== VALIDAÇÃO DE CASOS ESPECÍFICOS ===' AS tipo_validacao,
    CAST(NULL AS STRING) AS paciente,
    CAST(NULL AS STRING) AS cpf,
    CAST(NULL AS INT64) AS gestacoes_antes,
    CAST(NULL AS INT64) AS gestacoes_depois,
    CAST(NULL AS STRING) AS status,
    CAST(NULL AS STRING) AS datas_inicio

UNION ALL

-- Linha em branco
SELECT '', '', '', NULL, NULL, '', ''

UNION ALL

-- Caso 1: Alessa Oliveira da Costa (esperado: 1 gestação)
SELECT
    'Caso 1: Alessa Oliveira da Costa',
    ARRAY_AGG(DISTINCT nome LIMIT 1)[OFFSET(0)],
    '20469417722',
    12,  -- Antes: 12 registros duplicados
    COUNT(*),  -- Depois: deve ser 1
    CASE
        WHEN COUNT(*) = 1 THEN '✅ CORRIGIDO'
        ELSE CONCAT('❌ AINDA TEM ', CAST(COUNT(*) AS STRING), ' DUPLICAÇÕES')
    END,
    STRING_AGG(DISTINCT CAST(data_inicio AS STRING), ', ')
FROM resultado_corrigido
WHERE cpf = '20469417722'
GROUP BY cpf

UNION ALL

-- Caso 2: Lara Jane Pereira Silva (esperado: 1 gestação)
SELECT
    'Caso 2: Lara Jane Pereira Silva',
    ARRAY_AGG(DISTINCT nome LIMIT 1)[OFFSET(0)],
    '17361746730',
    17,  -- Antes: 17 registros duplicados (PIOR CASO)
    COUNT(*),  -- Depois: deve ser 1
    CASE
        WHEN COUNT(*) = 1 THEN '✅ CORRIGIDO'
        ELSE CONCAT('❌ AINDA TEM ', CAST(COUNT(*) AS STRING), ' DUPLICAÇÕES')
    END,
    STRING_AGG(DISTINCT CAST(data_inicio AS STRING), ', ')
FROM resultado_corrigido
WHERE cpf = '17361746730'
GROUP BY cpf

UNION ALL

-- Caso 3: Suzane dos Santos Napolitano (esperado: 1 gestação)
SELECT
    'Caso 3: Suzane dos Santos Napolitano',
    ARRAY_AGG(DISTINCT nome LIMIT 1)[OFFSET(0)],
    '12535785757',
    10,  -- Antes: 10 registros duplicados
    COUNT(*),  -- Depois: deve ser 1
    CASE
        WHEN COUNT(*) = 1 THEN '✅ CORRIGIDO'
        ELSE CONCAT('❌ AINDA TEM ', CAST(COUNT(*) AS STRING), ' DUPLICAÇÕES')
    END,
    STRING_AGG(DISTINCT CAST(data_inicio AS STRING), ', ')
FROM resultado_corrigido
WHERE cpf = '12535785757'
GROUP BY cpf

UNION ALL

-- Caso 4: Antonia Erileuda Rodrigues (esperado: 1 gestação)
SELECT
    'Caso 4: Antonia Erileuda Rodrigues',
    ARRAY_AGG(DISTINCT nome LIMIT 1)[OFFSET(0)],
    '09606275701',
    2,  -- Antes: 2 registros duplicados
    COUNT(*),  -- Depois: deve ser 1
    CASE
        WHEN COUNT(*) = 1 THEN '✅ CORRIGIDO'
        ELSE CONCAT('❌ AINDA TEM ', CAST(COUNT(*) AS STRING), ' DUPLICAÇÕES')
    END,
    STRING_AGG(DISTINCT CAST(data_inicio AS STRING), ', ')
FROM resultado_corrigido
WHERE cpf = '09606275701'
GROUP BY cpf

UNION ALL

-- Linha em branco
SELECT '', '', '', NULL, NULL, '', ''

UNION ALL

-- Estatísticas gerais após correção
SELECT
    '=== ESTATÍSTICAS GERAIS ===',
    '',
    '',
    NULL,
    NULL,
    '',
    ''

UNION ALL

SELECT
    'Total de registros',
    '',
    '',
    NULL,
    COUNT(*),
    'Deve ser significativamente menor que antes',
    ''
FROM resultado_corrigido

UNION ALL

SELECT
    'Pacientes únicos',
    '',
    '',
    NULL,
    COUNT(DISTINCT id_paciente),
    'Deve ser próximo ao total de registros',
    ''
FROM resultado_corrigido

UNION ALL

SELECT
    'Gestações únicas',
    '',
    '',
    NULL,
    COUNT(DISTINCT id_gestacao),
    'Deve ser igual ao total de registros',
    ''
FROM resultado_corrigido

UNION ALL

-- Linha em branco
SELECT '', '', '', NULL, NULL, '', ''

UNION ALL

-- Check de duplicações residuais
SELECT
    '=== CHECK DE DUPLICAÇÕES RESIDUAIS ===',
    '',
    '',
    NULL,
    NULL,
    '',
    ''

UNION ALL

SELECT
    'Casos com múltiplas gestações na mesma data',
    '',
    '',
    NULL,
    COUNT(*),
    CASE
        WHEN COUNT(*) = 0 THEN '✅ NENHUMA DUPLICAÇÃO ENCONTRADA'
        ELSE CONCAT('⚠️ ATENÇÃO: ', CAST(COUNT(*) AS STRING), ' CASOS COM POSSÍVEL DUPLICAÇÃO')
    END,
    ''
FROM (
    SELECT
        id_paciente,
        data_inicio,
        COUNT(*) AS ocorrencias
    FROM resultado_corrigido
    GROUP BY id_paciente, data_inicio
    HAVING COUNT(*) > 1
)

ORDER BY tipo_validacao, paciente;
