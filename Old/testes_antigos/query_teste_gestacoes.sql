DECLARE data_referencia DATE DEFAULT DATE('2025-07-01');

WITH

    -- ------------------------------------------------------------
    -- Recuperando dados do Paciente
    -- ------------------------------------------------------------
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

    -- ------------------------------------------------------------
    -- Eventos de Gestação COM FILTRO TEMPORAL
    -- ------------------------------------------------------------
    -- Janela: [data_referencia - 340 dias, data_referencia]
    -- Justificativa: 299 dias (gestação) + 42 dias (puerpério) = 341 dias
    -- ------------------------------------------------------------
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
            -- Filtro de janela temporal
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) <= data_referencia
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
    ),

    -- ------------------------------------------------------------
    -- Eventos de DESFECHO da Gestação
    -- ------------------------------------------------------------
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

    -- ------------------------------------------------------------
    -- Inícios de Gestação (apenas CIDs ATIVOS)
    -- ------------------------------------------------------------
    inicios_brutos AS (
        SELECT *
        FROM eventos_brutos
        WHERE
            tipo_evento = 'gestacao'
            AND situacao_cid = 'ATIVO'
    ),

    -- ------------------------------------------------------------
    -- Inícios de Gestação com Grupo
    -- ------------------------------------------------------------
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

    -- ------------------------------------------------------------
    -- Grupos de Inícios de Gestação
    -- ------------------------------------------------------------
    grupos_inicios AS (
        SELECT *, SUM(nova_ocorrencia_flag) OVER (
                PARTITION BY id_paciente
                ORDER BY data_evento
            ) AS grupo_id
        FROM inicios_com_grupo
    ),

    -- ------------------------------------------------------------
    -- Inícios de Gestação Deduplicados
    -- ------------------------------------------------------------
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

    -- ------------------------------------------------------------
    -- Primeiro desfecho por gestação
    -- ------------------------------------------------------------
    -- ✅ CORREÇÃO: Removido id_hci do GROUP BY para evitar duplicações
    -- Múltiplos episódios assistenciais (id_hci) da mesma gestação
    -- eram tratados como gestações separadas
    -- ------------------------------------------------------------
    primeiro_desfecho AS (
        SELECT
            -- Seleciona apenas UM id_hci por gestação (primeiro cronologicamente)
            ARRAY_AGG(i.id_hci ORDER BY i.data_evento LIMIT 1)[OFFSET(0)] AS id_hci,
            i.id_paciente,
            i.data_evento AS data_inicio,
            MIN(d.data_desfecho) AS data_fim,
            ARRAY_AGG(d.tipo_desfecho ORDER BY d.data_desfecho LIMIT 1)[OFFSET(0)] AS tipo_desfecho,
            ARRAY_AGG(d.cid_desfecho ORDER BY d.data_desfecho LIMIT 1)[OFFSET(0)] AS cid_desfecho
        FROM inicios_deduplicados i  -- ✅ Usar inicios_deduplicados ao invés de eventos_brutos
        LEFT JOIN eventos_desfecho d
            ON i.id_paciente = d.id_paciente
            AND d.data_desfecho > i.data_evento
            AND DATE_DIFF(d.data_desfecho, i.data_evento, DAY) <= 320
        WHERE i.data_evento <= data_referencia
            AND i.tipo_evento = 'gestacao'
        GROUP BY i.id_paciente, i.data_evento  -- ✅ APENAS id_paciente e data_inicio
    ),

    -- ------------------------------------------------------------
    -- Gestações Únicas com Desfecho Real
    -- ------------------------------------------------------------
    -- ✅ CORREÇÃO: Usar inicios_deduplicados para evitar duplicações
    -- ------------------------------------------------------------
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
        INNER JOIN inicios_deduplicados id  -- ✅ Usar inicios_deduplicados
            ON pd.id_hci = id.id_hci
            AND pd.id_paciente = id.id_paciente
            AND pd.data_inicio = id.data_evento
    ),

    -- ------------------------------------------------------------
    -- Gestações com Status
    -- ------------------------------------------------------------
    gestacoes_com_status AS (
        SELECT
            *,
            -- data_fim_efetiva: usado para auto-encerramento após 299 dias
            CASE
                WHEN data_fim IS NOT NULL THEN data_fim
                WHEN DATE_ADD(data_inicio, INTERVAL 299 DAY) <= data_referencia
                THEN DATE_ADD(data_inicio, INTERVAL 299 DAY)
                ELSE NULL
            END AS data_fim_efetiva,
            DATE_ADD(data_inicio, INTERVAL 40 WEEK) AS dpp
        FROM gestacoes_unicas
    ),

    -- ------------------------------------------------------------
    -- ✅ REGRA 2: Definição de Fase Atual (LÓGICA EXATA - SEM GAP)
    -- ------------------------------------------------------------
    -- Gestação:  data_inicio <= data_referencia <= data_fim
    -- Puerpério: data_fim < data_referencia <= (data_fim + 42 dias)
    -- Encerrada: data_referencia > (data_fim + 42 dias)
    --
    -- IMPORTANTE: Sem gap! Transição direta de Puerpério para Encerrada aos 42 dias
    -- ------------------------------------------------------------
    gestacoes_com_fase AS (
        SELECT
            gcs.*,
            CASE
                -- Gestação: em curso na data_referencia
                WHEN gcs.data_inicio <= data_referencia
                AND (
                    gcs.data_fim IS NULL OR gcs.data_fim >= data_referencia
                )
                -- Proteção: não pode exceder 299 dias
                AND DATE_ADD(gcs.data_inicio, INTERVAL 299 DAY) >= data_referencia
                THEN 'Gestação'

                -- Puerpério: até 42 dias após data_fim (INCLUSIVE)
                WHEN gcs.data_fim IS NOT NULL
                AND gcs.data_fim < data_referencia
                AND DATE_ADD(gcs.data_fim, INTERVAL 42 DAY) >= data_referencia
                THEN 'Puerpério'

                -- Encerrada: mais de 42 dias após data_fim
                WHEN gcs.data_fim IS NOT NULL
                AND DATE_ADD(gcs.data_fim, INTERVAL 42 DAY) < data_referencia
                THEN 'Encerrada'

                -- Gestação auto-encerrada (sem data_fim mas passou 299 dias)
                WHEN gcs.data_fim IS NULL
                AND DATE_ADD(gcs.data_inicio, INTERVAL 299 DAY) < data_referencia
                THEN 'Encerrada'

                ELSE 'Status indefinido'
            END AS fase_atual,

            -- Trimestre e IG baseados em data_referencia
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

    -- ------------------------------------------------------------
    -- ✅ REGRA 3: Filtrar para Incluir APENAS Gestação e Puerpério
    -- ------------------------------------------------------------
    -- Excluir: fase_atual = 'Encerrada'
    -- Incluir: fase_atual = 'Gestação' OU 'Puerpério'
    -- ------------------------------------------------------------
    filtrado AS (
        SELECT *
        FROM gestacoes_com_fase
        WHERE fase_atual IN ('Gestação', 'Puerpério')
    ),

-- ============================================================
-- ANÁLISE ESTATÍSTICA DOS RESULTADOS
-- ============================================================
    analise_estatistica AS (
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
            CAST(NULL AS DATE)
        FROM filtrado

        UNION ALL

        SELECT
            'Pacientes únicos',
            COUNT(DISTINCT id_paciente),
            CAST(COUNT(DISTINCT id_paciente) AS STRING),
            CAST(NULL AS DATE)
        FROM filtrado

        UNION ALL

        SELECT
            'Gestações únicas',
            COUNT(DISTINCT id_gestacao),
            CAST(COUNT(DISTINCT id_gestacao) AS STRING),
            CAST(NULL AS DATE)
        FROM filtrado

        UNION ALL

        SELECT
            '',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            '=== DISTRIBUIÇÃO POR FASE ===',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            fase_atual,
            COUNT(*),
            CONCAT(CAST(COUNT(*) AS STRING), ' (', CAST(ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS STRING), '%)'),
            CAST(NULL AS DATE)
        FROM filtrado
        GROUP BY fase_atual

        UNION ALL

        SELECT
            '',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            '=== DISTRIBUIÇÃO POR TRIMESTRE (GESTAÇÕES) ===',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            trimestre_atual_gestacao,
            COUNT(*),
            CONCAT(CAST(COUNT(*) AS STRING), ' (', CAST(ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS STRING), '%)'),
            CAST(NULL AS DATE)
        FROM filtrado
        WHERE fase_atual = 'Gestação'
        GROUP BY trimestre_atual_gestacao

        UNION ALL

        SELECT
            '',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            '=== DATAS DE INÍCIO ===',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            'Data mínima',
            NULL,
            '',
            MIN(data_inicio)
        FROM filtrado

        UNION ALL

        SELECT
            'Data máxima',
            NULL,
            '',
            MAX(data_inicio)
        FROM filtrado

        UNION ALL

        SELECT
            'Range (dias)',
            DATE_DIFF(MAX(data_inicio), MIN(data_inicio), DAY),
            CAST(DATE_DIFF(MAX(data_inicio), MIN(data_inicio), DAY) AS STRING),
            CAST(NULL AS DATE)
        FROM filtrado

        UNION ALL

        SELECT
            '',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            '=== IDADE GESTACIONAL (GESTAÇÕES ATIVAS) ===',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            'IG Média (semanas)',
            CAST(ROUND(AVG(ig_atual_semanas), 2) AS INT64),
            CAST(ROUND(AVG(ig_atual_semanas), 2) AS STRING),
            CAST(NULL AS DATE)
        FROM filtrado
        WHERE fase_atual = 'Gestação'

        UNION ALL

        SELECT
            'IG Mínima (semanas)',
            MIN(ig_atual_semanas),
            CAST(MIN(ig_atual_semanas) AS STRING),
            CAST(NULL AS DATE)
        FROM filtrado
        WHERE fase_atual = 'Gestação'

        UNION ALL

        SELECT
            'IG Máxima (semanas)',
            MAX(ig_atual_semanas),
            CAST(MAX(ig_atual_semanas) AS STRING),
            CAST(NULL AS DATE)
        FROM filtrado
        WHERE fase_atual = 'Gestação'

        UNION ALL

        SELECT
            '',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            '=== TIPOS DE DESFECHO ===',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            IFNULL(tipo_desfecho, 'Sem desfecho'),
            COUNT(*),
            CONCAT(CAST(COUNT(*) AS STRING), ' (', CAST(ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS STRING), '%)'),
            CAST(NULL AS DATE)
        FROM filtrado
        GROUP BY tipo_desfecho

        UNION ALL

        SELECT
            '',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            '=== VALIDAÇÃO DE DEDUPLICAÇÃO ===',
            CAST(NULL AS INT64),
            '',
            CAST(NULL AS DATE)

        UNION ALL

        SELECT
            'Casos com múltiplas gestações na mesma data',
            COUNT(*),
            CASE
                WHEN COUNT(*) = 0 THEN '✅ NENHUMA DUPLICAÇÃO ENCONTRADA'
                ELSE CONCAT('⚠️ ATENÇÃO: ', CAST(COUNT(*) AS STRING), ' CASOS COM POSSÍVEL DUPLICAÇÃO')
            END,
            CAST(NULL AS DATE)
        FROM (
            SELECT
                id_paciente,
                data_inicio,
                COUNT(*) AS ocorrencias
            FROM filtrado
            GROUP BY id_paciente, data_inicio
            HAVING COUNT(*) > 1
        )
    )

-- ============================================================
-- SELEÇÃO FINAL
-- ============================================================
-- Descomente a seção desejada:

-- OPÇÃO 1: Retornar dados completos das gestações
-- ------------------------------------------------------------
SELECT
    data_referencia AS data_snapshot,
    id_hci,
    id_gestacao,
    id_paciente,
    cpf,
    nome,
    idade_gestante,
    numero_gestacao,
    data_inicio,
    data_fim,
    data_fim_efetiva,
    tipo_desfecho,
    cid_desfecho,
    dpp,
    fase_atual,
    trimestre_atual_gestacao,
    ig_atual_semanas,
    ig_final_semanas
FROM filtrado;

-- OPÇÃO 2: Retornar apenas análise estatística
-- ------------------------------------------------------------
-- SELECT
--     metrica,
--     valor_numerico,
--     valor_texto,
--     valor_data
-- FROM analise_estatistica
-- ORDER BY metrica;