-- ============================================================
-- VERSÃO CORRIGIDA: Histórico Conceitualmente Coerente
-- ============================================================
-- CORREÇÃO PRINCIPAL: Filtra eventos por janela temporal relevante
-- para data_referencia, garantindo snapshot conceitualmente correto
--
-- MUDANÇAS:
-- 1. Adiciona filtro de janela temporal nos eventos_brutos
-- 2. Ajusta lógica de visibilidade de gestações no snapshot
-- 3. Documenta conceito de "gestação visível" em cada data
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
    -- CORREÇÃO CRÍTICA: Adiciona filtro por janela temporal relevante
    -- Janela: [data_referencia - 310 dias, data_referencia]
    -- Justificativa: 299 dias (gestação) + 45 dias (puerpério) = 344 dias, usando 310 como margem conservadora
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
            -- ✅ NOVO: Filtro de janela temporal
            -- Considera eventos que possam estar "visíveis" na data_referencia
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) <= data_referencia
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) >= DATE_SUB(data_referencia, INTERVAL 310 DAY)
    ),

    -- ------------------------------------------------------------
    -- Inícios e Finais de Gestação
    -- ------------------------------------------------------------
    inicios_brutos AS (
        SELECT *
        FROM eventos_brutos
        WHERE
            tipo_evento = 'gestacao'
            AND situacao_cid = 'ATIVO'
    ),
    finais AS (
        SELECT *
        FROM eventos_brutos
        WHERE
            tipo_evento = 'gestacao'
            AND situacao_cid = 'RESOLVIDO'
    ),

    -- ------------------------------------------------------------
    -- Inícios de Gestação com Grupo
    -- ------------------------------------------------------------
    inicios_com_grupo AS (
        SELECT
            *,
            LAG(data_evento) OVER (
                PARTITION BY
                    id_paciente
                ORDER BY data_evento
            ) AS data_anterior,
            CASE
                WHEN LAG(data_evento) OVER (
                    PARTITION BY
                        id_paciente
                    ORDER BY data_evento
                ) IS NULL THEN 1
                WHEN DATE_DIFF (
                    data_evento,
                    LAG(data_evento) OVER (
                        PARTITION BY
                            id_paciente
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
                PARTITION BY
                    id_paciente
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
                        PARTITION BY
                            id_paciente, grupo_id
                        ORDER BY data_evento DESC
                    ) AS rn
                FROM grupos_inicios
            )
        WHERE
            rn = 1
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
            i.data_evento AS data_inicio,
            (
                SELECT MIN(f.data_evento)
                FROM finais f
                WHERE
                    f.id_paciente = i.id_paciente
                    AND f.data_evento > i.data_evento
            ) AS data_fim,
            ROW_NUMBER() OVER (
                PARTITION BY
                    i.id_paciente
                ORDER BY i.data_evento
            ) AS numero_gestacao,
            CONCAT(
                i.id_paciente,
                '-',
                CAST(
                    ROW_NUMBER() OVER (
                        PARTITION BY
                            i.id_paciente
                        ORDER BY i.data_evento
                    ) AS STRING
                )
            ) AS id_gestacao
        FROM inicios_deduplicados i
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
    -- Definição de Fase e Trimestre da Gestação
    -- COM FILTRO DE VISIBILIDADE NO SNAPSHOT
    -- ------------------------------------------------------------
    -- ✅ NOVO: Adiciona lógica para incluir apenas gestações "visíveis"
    -- na data_referencia (fase = Gestação OU Puerpério)
    -- ------------------------------------------------------------
    filtrado AS (
        SELECT
            gcs.*,
            CASE
                WHEN gcs.data_fim IS NULL
                AND DATE_ADD(
                    gcs.data_inicio,
                    INTERVAL 299 DAY
                ) > data_referencia THEN 'Gestação'
                WHEN gcs.data_fim IS NOT NULL
                AND DATE_DIFF (
                    data_referencia,
                    gcs.data_fim,
                    DAY
                ) <= 45 THEN 'Puerpério'
                ELSE 'Encerrada'
            END AS fase_atual,
            CASE
                WHEN DATE_DIFF (
                    data_referencia,
                    gcs.data_inicio,
                    WEEK
                ) <= 13 THEN '1º trimestre'
                WHEN DATE_DIFF (
                    data_referencia,
                    gcs.data_inicio,
                    WEEK
                ) BETWEEN 14 AND 27  THEN '2º trimestre'
                WHEN DATE_DIFF (
                    data_referencia,
                    gcs.data_inicio,
                    WEEK
                ) >= 28 THEN '3º trimestre'
                ELSE 'Data inválida ou encerrada'
            END AS trimestre_atual_gestacao
        FROM gestacoes_com_status gcs
        -- ✅ NOVO: Filtra para incluir apenas gestações relevantes no snapshot
        WHERE
            -- Inclui se for Gestação (sem data_fim ou ainda não atingiu 299 dias)
            (
                gcs.data_fim IS NULL
                AND DATE_ADD(gcs.data_inicio, INTERVAL 299 DAY) > data_referencia
            )
            OR
            -- Inclui se for Puerpério (com data_fim e dentro de 45 dias)
            (
                gcs.data_fim IS NOT NULL
                AND DATE_DIFF(data_referencia, gcs.data_fim, DAY) <= 45
            )
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
        SELECT f.id_gestacao,
            eq.equipe_nome, eq.clinica_nome, ROW_NUMBER() OVER (
                PARTITION BY
                    f.id_gestacao
                ORDER BY eq.datahora_ultima_atualizacao DESC
            ) AS rn
        FROM
            filtrado f
                LEFT JOIN unnested_equipes eq ON f.id_paciente = eq.id_paciente
            AND DATE(
                eq.datahora_ultima_atualizacao
            ) <= COALESCE(
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
        WHERE
            rn = 1
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
    edf.equipe_nome,
    edf.clinica_nome
FROM filtrado
    LEFT JOIN equipe_durante_final edf ON filtrado.id_gestacao = edf.id_gestacao;

END;
