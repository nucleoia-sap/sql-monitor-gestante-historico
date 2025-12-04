-- VERSÃO CORRIGIDA: Filtro temporal aplicado APÓS calcular data_inicio
-- Problema identificado: filtro de 340 dias estava sendo aplicado sobre data_evento (CID)
-- ao invés de sobre data_inicio (DUM calculada)

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
    -- Eventos de Gestação SEM FILTRO TEMPORAL
    -- ------------------------------------------------------------
    -- ✅ CORREÇÃO: Remove filtro temporal aqui, aplica depois
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
            AND c.situacao IN ('ATIVO', 'RESOLVIDO')  -- ✅ Ambos, não apenas ATIVO
            AND (
                c.id = 'Z321'
                OR c.id LIKE 'Z34%'
                OR c.id LIKE 'Z35%'
            )
            AND paciente.id_paciente IS NOT NULL
            -- ✅ REMOVIDO: Filtro temporal será aplicado DEPOIS de calcular data_inicio
    ),

    -- ------------------------------------------------------------
    -- ✅ NOVA LÓGICA: Data de Início = MODA de data_diagnostico
    -- ------------------------------------------------------------
    eventos_gestacao AS (
        SELECT *
        FROM eventos_brutos
        WHERE tipo_evento = 'gestacao'
    ),

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

    inicios_por_moda AS (
        SELECT
            id_hci,
            id_paciente,
            cpf,
            nome,
            idade_gestante,
            dum_estimada AS data_evento,
            frequencia AS vezes_registrada
        FROM moda_por_grupo_gestacao
        WHERE rn = 1
    ),

    -- ------------------------------------------------------------
    -- Finais de Gestação (CIDs RESOLVIDOS)
    -- ------------------------------------------------------------
    finais AS (
        SELECT *
        FROM eventos_brutos
        WHERE
            tipo_evento = 'gestacao'
            AND situacao_cid = 'RESOLVIDO'
    ),

    -- ------------------------------------------------------------
    -- Gestações Únicas
    -- ------------------------------------------------------------
    gestacoes_unicas AS (
        SELECT
            i.id_hci,
            i.id_paciente,
            i.cpf,
            i.nome,
            i.idade_gestante,
            i.data_evento AS data_inicio,  -- DUM estimada (MODA)
            i.vezes_registrada,
            (
                SELECT MIN(f.data_evento)
                FROM finais f
                WHERE
                    f.id_paciente = i.id_paciente
                    AND f.data_evento > i.data_evento
            ) AS data_fim,
            ROW_NUMBER() OVER (
                PARTITION BY i.id_paciente
                ORDER BY i.data_evento
            ) AS numero_gestacao,
            CONCAT(
                i.id_paciente,
                '-',
                CAST(
                    ROW_NUMBER() OVER (
                        PARTITION BY i.id_paciente
                        ORDER BY i.data_evento
                    ) AS STRING
                )
            ) AS id_gestacao
        FROM inicios_por_moda i
    ),

    -- ------------------------------------------------------------
    -- Gestações com Status
    -- ------------------------------------------------------------
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

    -- ------------------------------------------------------------
    -- Definição de Fase Atual (LÓGICA EXATA - SEM GAP)
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
    -- ✅ NOVO: Filtro Temporal Aplicado AQUI (após data_inicio calculada)
    -- ------------------------------------------------------------
    -- Inclui apenas gestações com data_inicio nos últimos 340 dias
    -- Justificativa: 299 dias (gestação) + 42 dias (puerpério) = 341 dias
    -- ------------------------------------------------------------
    filtrado_temporal AS (
        SELECT *
        FROM gestacoes_com_fase
        WHERE data_inicio >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
          AND data_inicio <= data_referencia
    ),

    -- ------------------------------------------------------------
    -- Filtrar para Incluir APENAS Gestação e Puerpério
    -- ------------------------------------------------------------
    filtrado AS (
        SELECT *
        FROM filtrado_temporal
        WHERE fase_atual IN ('Gestação', 'Puerpério')
    ),

    -- ------------------------------------------------------------
    -- Descobrindo Equipe da Saúde da Gestação
    -- ------------------------------------------------------------
    unnested_equipes AS (
        SELECT
            p.dados.id_paciente AS id_paciente,
            eq.datahora_ultima_atualizacao,
            eq.nome AS equipe_nome,
            eq.clinica_familia.nome AS clinica_nome
        FROM
            `rj-sms.saude_historico_clinico.paciente` p
            LEFT JOIN UNNEST (p.equipe_saude_familia) AS eq
    ),
    equipe_durante_gestacao AS (
        SELECT
            f.id_gestacao,
            eq.equipe_nome,
            eq.clinica_nome,
            ROW_NUMBER() OVER (
                PARTITION BY f.id_gestacao
                ORDER BY eq.datahora_ultima_atualizacao DESC
            ) AS rn
        FROM
            filtrado f
            LEFT JOIN unnested_equipes eq ON f.id_paciente = eq.id_paciente
            AND DATE(eq.datahora_ultima_atualizacao) <= COALESCE(
                f.data_fim_efetiva,
                data_referencia
            )
    ),
    equipe_durante_final AS (
        SELECT
            id_gestacao,
            equipe_nome,
            clinica_nome
        FROM equipe_durante_gestacao
        WHERE rn = 1
    )

-- ------------------------------------------------------------
-- Finalização do Modelo
-- ------------------------------------------------------------
SELECT
    data_referencia AS data_snapshot,
    filtrado.id_hci,
    filtrado.id_gestacao,
    filtrado.id_paciente,
    filtrado.cpf,
    filtrado.nome,
    filtrado.idade_gestante,
    filtrado.numero_gestacao,
    filtrado.data_inicio,
    filtrado.data_fim,
    filtrado.data_fim_efetiva,
    filtrado.dpp,
    filtrado.fase_atual,
    filtrado.trimestre_atual_gestacao,
    filtrado.ig_atual_semanas,
    filtrado.ig_final_semanas,
    filtrado.vezes_registrada,
    edf.equipe_nome,
    edf.clinica_nome
FROM filtrado
    LEFT JOIN equipe_durante_final edf ON filtrado.id_gestacao = edf.id_gestacao;
