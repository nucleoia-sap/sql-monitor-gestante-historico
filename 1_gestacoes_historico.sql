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
            AND c.situacao = 'ATIVO'  -- ✅ CORREÇÃO: Apenas ATIVO para inícios
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
    -- ✅ NOVA LÓGICA: Data de Início = MODA de data_diagnostico
    -- ------------------------------------------------------------
    -- A DUM (Data da Última Menstruação) é refinada ao longo dos atendimentos:
    -- 1ª consulta: DUM imprecisa (relato da paciente)
    -- Consultas seguintes: DUM vai sendo refinada
    -- Após USG: DUM fica precisa e se repete em todos atendimentos
    -- MODA (valor mais frequente) = melhor estimativa consolidada
    -- ------------------------------------------------------------

    -- Passo 1: Filtrar apenas eventos de gestação
    eventos_gestacao AS (
        SELECT *
        FROM eventos_brutos
        WHERE tipo_evento = 'gestacao'
    ),

    -- Passo 2: Agrupar eventos em períodos de gestação (janela de 60 dias)
    -- Se diferença entre eventos > 60 dias, considera nova gestação
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

    -- Passo 3: Criar ID de período de gestação
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

    -- Passo 4: Calcular frequência de cada data_evento DENTRO de cada grupo de gestação
    frequencia_datas AS (
        SELECT
            id_paciente,
            grupo_gestacao,
            data_evento,
            COUNT(*) AS frequencia,
            -- Pega qualquer id_hci, cpf, nome (são iguais para mesma paciente)
            ANY_VALUE(id_hci) AS id_hci,
            ANY_VALUE(cpf) AS cpf,
            ANY_VALUE(nome) AS nome,
            ANY_VALUE(idade_gestante) AS idade_gestante
        FROM eventos_com_grupo_gestacao
        GROUP BY id_paciente, grupo_gestacao, data_evento
    ),

    -- Passo 5: Para cada grupo de gestação, pegar a data com MAIOR frequência (MODA)
    moda_por_grupo_gestacao AS (
        SELECT
            id_paciente,
            grupo_gestacao,
            data_evento AS dum_estimada,  -- DUM = data mais frequente dentro do grupo
            frequencia,
            id_hci,
            cpf,
            nome,
            idade_gestante,
            ROW_NUMBER() OVER (
                PARTITION BY id_paciente, grupo_gestacao
                ORDER BY frequencia DESC, data_evento DESC  -- Em caso de empate, pega a mais recente
            ) AS rn
        FROM frequencia_datas
    ),

    -- Passo 6: Selecionar apenas a MODA de cada grupo (rn = 1)
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
    -- ✅ CORREÇÃO: Buscar RESOLVIDO diretamente da fonte, não de eventos_brutos
    -- eventos_brutos agora tem apenas ATIVO
    -- ------------------------------------------------------------
    finais AS (
        SELECT
            paciente.id_paciente AS id_paciente,
            SAFE.PARSE_DATE (
                '%Y-%m-%d',
                SUBSTR(c.data_diagnostico, 1, 10)
            ) AS data_evento
        FROM
            `rj-sms.saude_historico_clinico.episodio_assistencial`
            LEFT JOIN UNNEST (condicoes) c
        WHERE
            c.data_diagnostico IS NOT NULL
            AND c.data_diagnostico != ''
            AND c.situacao = 'RESOLVIDO'
            AND (
                c.id = 'Z321'
                OR c.id LIKE 'Z34%'
                OR c.id LIKE 'Z35%'
            )
            AND paciente.id_paciente IS NOT NULL
            -- Filtro temporal: mesma janela que eventos_brutos
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) <= data_referencia
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
    ),

    -- ------------------------------------------------------------
    -- Gestações Únicas
    -- ------------------------------------------------------------
    -- ✅ SIMPLIFICAÇÃO: inicios_por_moda já tem gestações corretamente separadas
    -- Agrupamento de 60 dias + MODA já foi aplicado nos passos 2-6
    -- NÃO precisa agrupar novamente!
    -- ------------------------------------------------------------
    gestacoes_unicas AS (
        SELECT
            i.id_hci,
            i.id_paciente,
            i.cpf,
            i.nome,
            i.idade_gestante,
            i.data_evento AS data_inicio,  -- DUM estimada (MODA)
            i.vezes_registrada,  -- Quantas vezes essa DUM foi registrada
            -- Subconsulta para encontrar a data de fim mais próxima após o início
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
    filtrado.dpp,
    filtrado.fase_atual,
    filtrado.trimestre_atual_gestacao,
    filtrado.ig_atual_semanas,
    filtrado.ig_final_semanas,
    filtrado.vezes_registrada,  -- ✅ NOVO: quantas vezes a DUM foi registrada
    edf.equipe_nome,
    edf.clinica_nome
FROM filtrado
    LEFT JOIN equipe_durante_final edf ON filtrado.id_gestacao = edf.id_gestacao;




-- END;
