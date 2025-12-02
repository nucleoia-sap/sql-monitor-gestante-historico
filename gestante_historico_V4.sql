-- ============================================================
-- VERSÃO V3 FINAL CORRIGIDA: Lógica Conceitual Definitiva
-- ============================================================
-- REGRAS DEFINITIVAS (CORRETAS):
--
-- 1. FILTRO TEMPORAL:
--    - Incluir apenas gestações com data_inicio <= data_referencia
--
-- 2. FASE_ATUAL (SEM GAP):
--    - Gestação:   data_inicio <= data_referencia <= data_fim
--    - Puerpério:  data_fim < data_referencia <= (data_fim + 42 dias)
--    - Encerrada:  data_referencia > (data_fim + 42 dias)
--
-- 3. EXCLUSÃO:
--    - NÃO incluir gestações com fase_atual = 'Encerrada' no snapshot
--
-- RESULTADO: Snapshot contém apenas Gestação + Puerpério
-- ============================================================

CREATE OR REPLACE PROCEDURE `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_referencia DATE)

BEGIN

CREATE OR REPLACE TABLE `rj-sms-sandbox.sub_pav_us._gestacoes_historico` AS

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
            ) AS idade_gestante,
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
    -- inicios_brutos AS (
    --     SELECT *
    --     FROM eventos_brutos
    --     WHERE
    --         tipo_evento = 'gestacao'
    --         AND situacao_cid = 'ATIVO'
    -- ),

    -- ------------------------------------------------------------
    -- Inícios de Gestação com Grupo
    -- ------------------------------------------------------------
    -- inicios_com_grupo AS (
    --     SELECT
    --         *,
    --         LAG(data_evento) OVER (
    --             PARTITION BY id_paciente
    --             ORDER BY data_evento
    --         ) AS data_anterior,
    --         CASE
    --             WHEN LAG(data_evento) OVER (
    --                 PARTITION BY id_paciente
    --                 ORDER BY data_evento
    --             ) IS NULL THEN 1
    --             WHEN DATE_DIFF (
    --                 data_evento,
    --                 LAG(data_evento) OVER (
    --                     PARTITION BY id_paciente
    --                     ORDER BY data_evento
    --                 ),
    --                 DAY
    --             ) >= 60 THEN 1
    --             ELSE 0
    --         END AS nova_ocorrencia_flag
    --     FROM inicios_brutos
    -- ),

    -- ------------------------------------------------------------
    -- Grupos de Inícios de Gestação
    -- ------------------------------------------------------------
    -- grupos_inicios AS (
    --     SELECT *, SUM(nova_ocorrencia_flag) OVER (
    --             PARTITION BY id_paciente
    --             ORDER BY data_evento
    --         ) AS grupo_id
    --     FROM inicios_com_grupo
    -- ),

    -- ------------------------------------------------------------
    -- Inícios de Gestação Deduplicados
    -- ------------------------------------------------------------
    -- inicios_deduplicados AS (
    --     SELECT *
    --     FROM (
    --             SELECT *, ROW_NUMBER() OVER (
    --                     PARTITION BY id_paciente, grupo_id
    --                     ORDER BY data_evento DESC
    --                 ) AS rn
    --             FROM grupos_inicios
    --         )
    --     WHERE rn = 1
    -- ),

    -- ------------------------------------------------------------
    -- Gestações Únicas com Desfecho Real
    -- ------------------------------------------------------------
    gestacoes_unicas AS (
        SELECT
            i.id_hci,
            i.id_paciente,
            i.cpf,
            i.nome,
            i.idade_gestante,
            i.data_evento AS data_inicio,
            -- Busca primeiro evento de desfecho APÓS o início
            (
                SELECT MIN(d.data_desfecho)
                FROM eventos_desfecho d
                WHERE
                    d.id_paciente = i.id_paciente
                    AND d.data_desfecho > i.data_evento
                    AND DATE_DIFF(d.data_desfecho, i.data_evento, DAY) <= 320
            ) AS data_fim,
            -- Tipo de desfecho
            (
                SELECT d.tipo_desfecho
                FROM eventos_desfecho d
                WHERE
                    d.id_paciente = i.id_paciente
                    AND d.data_desfecho > i.data_evento
                    AND DATE_DIFF(d.data_desfecho, i.data_evento, DAY) <= 320
                ORDER BY d.data_desfecho
                LIMIT 1
            ) AS tipo_desfecho,
            -- CID do desfecho
            (
                SELECT d.cid_desfecho
                FROM eventos_desfecho d
                WHERE
                    d.id_paciente = i.id_paciente
                    AND d.data_desfecho > i.data_evento
                    AND DATE_DIFF(d.data_desfecho, i.data_evento, DAY) <= 320
                ORDER BY d.data_desfecho
                LIMIT 1
            ) AS cid_desfecho,
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
        FROM eventos_brutos i
        -- ✅ REGRA 1: Apenas gestações que iniciaram antes ou na data_referencia
        WHERE i.data_evento <= data_referencia
            AND i.tipo_evento = 'gestacao'
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

    -- ------------------------------------------------------------
    -- Descobrindo Equipe da Saúde da Gestação
    -- ------------------------------------------------------------
    -- unnested_equipes AS (
    --     SELECT
    --         p.dados.id_paciente AS id_paciente,
    --         eq.datahora_ultima_atualizacao,
    --         eq.nome AS equipe_nome,
    --         eq.clinica_familia.nome AS clinica_nome
    --     FROM
    --         `rj-sms.saude_historico_clinico.paciente` p
    --         LEFT JOIN UNNEST (p.equipe_saude_familia) AS eq
    -- ),
    -- equipe_durante_gestacao AS (
    --     SELECT f.id_gestacao,
    --         eq.equipe_nome, eq.clinica_nome, ROW_NUMBER() OVER (
    --             PARTITION BY f.id_gestacao
    --             ORDER BY eq.datahora_ultima_atualizacao DESC
    --         ) AS rn
    --     FROM
    --         filtrado f
    --             LEFT JOIN unnested_equipes eq ON f.id_paciente = eq.id_paciente
    --         AND DATE(eq.datahora_ultima_atualizacao) <= COALESCE(
    --             f.data_fim_efetiva,
    --             data_referencia
    --         )
    -- ),
    -- equipe_durante_final AS (
    --     SELECT
    --         id_gestacao,
    --         equipe_nome,
    --         clinica_nome
    --     FROM equipe_durante_gestacao
    --     WHERE rn = 1
    -- )

-- ------------------------------------------------------------
-- Finalização do Modelo
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

END;
