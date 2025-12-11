-- Sintaxe para criar ou substituir uma consulta salva (procedimento)
-- VERSÃO PARAMETRIZADA PARA CONSTRUÇÃO DE HISTÓRICO
-- Parâmetro data_referencia: permite gerar snapshot dos dados em uma data específica
-- CREATE OR REPLACE PROCEDURE `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_referencia DATE)

-- BEGIN

--   -- A consulta que você quer salvar e reutilizar
--   -- Usa data_referencia no lugar de CURRENT_DATE() para permitir análise histórica


-- -- {{
-- --     config(
-- --         enabled=true,
-- --         alias="gestacoes_historico",
-- --     )
-- -- }}

-- CREATE OR REPLACE TABLE `rj-sms-sandbox.sub_pav_us._gestacoes_historico` AS
-- DECLARE data_referencia DATE DEFAULT DATE('2024-01-01');

-- CREATE OR REPLACE TABLE `rj-sms-sandbox.sub_pav_us._gestacoes_historico` AS
-- DELETE FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico` WHERE data_snapshot = data_referencia;

INSERT INTO `rj-sms-sandbox.sub_pav_us._gestacoes_historico` 

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
    --
    -- ✅ CORREÇÃO: NÃO filtra por situacao_cid = 'ATIVO'
    -- Pega TODOS os CIDs de gestação (ATIVO e RESOLVIDO) pois estamos
    -- olhando dados históricos onde gestações já podem ter sido encerradas
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
            AND c.situacao IN ('ATIVO','RESOLVIDO') 
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
    -- Inícios de Gestação (apenas CIDs ATIVOS)
    -- ------------------------------------------------------------
    -- inicios_brutos AS (
    --     SELECT *
    --     FROM eventos_brutos
    --     WHERE tipo_evento = 'gestacao'
    -- ),


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
    -- Inícios de Gestação com Grupo (janela de 60 dias)
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
    -- Inícios de Gestação Deduplicados (DATA MAIS RECENTE)
    -- ------------------------------------------------------------
    -- ✅ CORREÇÃO: Usar DATA MAIS RECENTE do grupo (não MODA)
    -- query_teste_gestacoes.sql usa esta abordagem
    -- ------------------------------------------------------------
    inicios_deduplicados AS (
        SELECT *
        FROM (
                SELECT *, ROW_NUMBER() OVER (
                        PARTITION BY id_paciente, grupo_id
                        ORDER BY data_evento DESC  -- ✅ DATA MAIS RECENTE
                    ) AS rn
                FROM grupos_inicios
            )
        WHERE rn = 1
    ),

    -- ------------------------------------------------------------
    -- Eventos de DESFECHO da Gestação (CIDs O00-O99)
    -- ------------------------------------------------------------
    -- ✅ CORREÇÃO: Usar CIDs de desfecho obstétrico (O00-O99) ao invés de Z3xx RESOLVIDO
    -- CIDs O00-O99 = eventos obstétricos concretos (aborto, parto, puerpério)
    -- CIDs Z3xx RESOLVIDO = marcação administrativa (menos precisa)
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
    -- Primeiro desfecho por gestação
    -- ------------------------------------------------------------
    -- ✅ CORREÇÃO: Remover id_hci do GROUP BY para evitar duplicações
    -- Múltiplos episódios assistenciais (id_hci) da mesma gestação
    -- eram tratados como gestações separadas
    -- Limitado a 320 dias entre início e desfecho (gestação máxima)
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
        FROM inicios_deduplicados i
        LEFT JOIN eventos_desfecho d
            ON i.id_paciente = d.id_paciente
            AND d.data_desfecho > i.data_evento
            AND DATE_DIFF(d.data_desfecho, i.data_evento, DAY) <= 320
        WHERE i.data_evento <= data_referencia
        GROUP BY i.id_paciente, i.data_evento  -- ✅ APENAS id_paciente e data_inicio
    ),

    -- ------------------------------------------------------------
    -- Gestações Únicas com Desfecho Real
    -- ------------------------------------------------------------
    -- ✅ CORREÇÃO: Usar primeiro_desfecho que já removeu duplicações por id_hci
    -- JOIN com inicios_deduplicados para recuperar informações completas
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
        INNER JOIN inicios_deduplicados id
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
            -- data_fim_efetiva: usado para auto-encerramento após 294 dias
            CASE
                WHEN data_fim IS NOT NULL THEN data_fim
                WHEN DATE_ADD(data_inicio, INTERVAL 294 DAY) <= data_referencia
                THEN DATE_ADD(data_inicio, INTERVAL 294 DAY)
                ELSE NULL
            END AS data_fim_efetiva,
            DATE_ADD(data_inicio, INTERVAL 40 WEEK) AS dpp
        FROM gestacoes_unicas
    ),

    -- ------------------------------------------------------------
    -- Definição de Fase Atual (LÓGICA EXATA - SEM GAP)
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
                -- Proteção: não pode exceder 294 dias (42 semanas)
                AND DATE_ADD(gcs.data_inicio, INTERVAL 294 DAY) >= data_referencia
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

                -- Gestação auto-encerrada (sem data_fim mas passou 294 dias)
                WHEN gcs.data_fim IS NULL
                AND DATE_ADD(gcs.data_inicio, INTERVAL 294 DAY) < data_referencia
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
    -- Filtrar para Incluir APENAS Gestação e Puerpério
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
            -- A equipe deve ter sido atualizada ANTES ou NO MÁXIMO na data de fim da gestação
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
-- Adiciona coluna data_snapshot para identificar o snapshot
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
    filtrado.tipo_desfecho,  -- ✅ NOVO: tipo de desfecho obstétrico
    filtrado.cid_desfecho,   -- ✅ NOVO: CID do desfecho
    filtrado.dpp,
    filtrado.fase_atual,
    filtrado.trimestre_atual_gestacao,
    filtrado.ig_atual_semanas,
    filtrado.ig_final_semanas,
    edf.equipe_nome,
    edf.clinica_nome
FROM filtrado
    LEFT JOIN equipe_durante_final edf ON filtrado.id_gestacao = edf.id_gestacao;

-- END;
