-- ============================================================
-- Script de Execução em Lote - Pipeline Histórico Pré-Natal
-- ============================================================
-- PROPÓSITO: Executar pipeline completo para lista de datas específicas
-- MATERIALIZAÇÃO: Apenas tabela 6 (linha_tempo_historico) é acumulada
--
-- INSTRUÇÕES:
-- 1. Edite a seção "CONFIGURAÇÃO USUÁRIO" com suas datas
-- 2. Execute o script completo no BigQuery Console
-- 3. Monitore o progresso através dos logs
-- ============================================================

-- ============================================================
-- CONFIGURAÇÃO USUÁRIO - EDITE AQUI
-- ============================================================

-- Lista de datas para processar (formato: 'YYYY-MM-DD')
-- Exemplo: últimos dias de cada mês de 2024
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2025-01-01'),
    DATE('2025-02-01'),
    DATE('2025-03-01'),
    DATE('2025-04-01'),
    DATE('2025-05-01'),
    DATE('2025-06-01'),
    DATE('2025-07-01'),
    DATE('2025-08-01'),
    DATE('2025-09-01'),
    DATE('2025-10-01')

    -- DATE('2024-02-29'),
    -- DATE('2024-03-31'),
    -- DATE('2024-04-30'),
    -- DATE('2024-05-31'),
    -- DATE('2024-06-30'),
    -- DATE('2024-07-31'),
    -- DATE('2024-08-31'),
    -- DATE('2024-09-30'),
    -- DATE('2024-10-31'),
    -- DATE('2024-11-30'),
    -- DATE('2024-12-31')
];

-- ============================================================
-- VARIÁVEIS DE CONTROLE (NÃO EDITAR)
-- ============================================================

DECLARE data_atual DATE;
DECLARE indice INT64 DEFAULT 0;
DECLARE total_datas INT64;
DECLARE inicio_processamento TIMESTAMP;
DECLARE fim_processamento TIMESTAMP;
DECLARE duracao_segundos INT64;
DECLARE registros_inseridos INT64;
DECLARE total_registros_acumulados INT64 DEFAULT 0;

-- Calcular total de datas
SET total_datas = ARRAY_LENGTH(datas_processar);

-- ============================================================
-- ETAPA 1: CRIAR TABELA ACUMULATIVA (SE NÃO EXISTIR)
-- ============================================================

SELECT '========================================' AS log_msg;
SELECT 'ETAPA 1: Criando/Verificando Tabela Acumulativa' AS log_msg;
SELECT '========================================' AS log_msg;

CREATE TABLE IF NOT EXISTS `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
(
    -- Colunas principais
    data_snapshot DATE,
    id_paciente STRING,
    cpf STRING,
    cns_string STRING,
    nome STRING,
    data_nascimento DATE,
    idade_gestante INT64,
    faixa_etaria STRING,
    raca STRING,
    numero_gestacao INT64,
    id_gestacao STRING,
    data_inicio DATE,
    data_fim DATE,
    data_fim_efetiva DATE,
    dpp DATE,
    fase_atual STRING,
    trimestre STRING,
    IG_atual_semanas INT64,
    IG_final_semanas INT64,

    -- Condições clínicas
    diabetes_previo INT64,
    diabetes_gestacional INT64,
    diabetes_nao_especificado INT64,
    diabetes_total INT64,
    hipertensao_previa INT64,
    preeclampsia INT64,
    hipertensao_nao_especificada INT64,
    hipertensao_total INT64,

    -- Controle pressórico
    qtd_pas_alteradas INT64,
    teve_pa_grave INT64,
    total_medicoes_pa INT64,
    percentual_pa_controlada FLOAT64,
    data_ultima_pa DATE,
    ultima_sistolica INT64,
    ultima_diastolica INT64,
    ultima_pa_controlada INT64,

    -- Medicações anti-hipertensivas
    tem_anti_hipertensivo INT64,
    tem_anti_hipertensivo_seguro INT64,
    tem_anti_hipertensivo_contraindicado INT64,
    anti_hipertensivos_seguros STRING,
    anti_hipertensivos_contraindicados STRING,
    provavel_hipertensa_sem_diagnostico INT64,
    tem_encaminhamento_has INT64,
    data_primeiro_encaminhamento_has DATE,
    cids_encaminhamento_has STRING,

    -- AAS e aparelhos
    tem_prescricao_aas INT64,
    data_primeira_prescricao_aas DATE,
    tem_aparelho_pa_dispensado INT64,
    data_primeira_dispensacao_pa DATE,
    qtd_aparelhos_pa_dispensados INT64,

    -- Medicações antidiabéticas
    tem_antidiabetico INT64,
    antidiabeticos_lista STRING,

    -- Fatores de risco para pré-eclâmpsia
    doenca_renal_cat INT64,
    doenca_autoimune_cat INT64,
    gravidez_gemelar_cat INT64,
    hipertensao_cronica_confirmada INT64,
    diabetes_previo_confirmado INT64,
    total_fatores_risco_pe INT64,
    tem_indicacao_aas INT64,
    adequacao_aas_pe STRING,

    -- Infecções
    hiv INT64,
    sifilis INT64,
    tuberculose INT64,

    -- Categorias de risco
    categorias_risco STRING,

    -- Pressão arterial máxima
    max_pressao_sistolica INT64,
    max_pressao_diastolica INT64,
    data_max_pa DATE,

    -- Consultas e prescrições
    total_consultas_prenatal INT64,
    prescricao_acido_folico STRING,
    prescricao_carbonato_calcio STRING,
    dias_desde_ultima_consulta INT64,
    mais_de_30_sem_atd STRING,

    -- Visitas ACS
    total_visitas_acs INT64,
    data_ultima_visita DATE,
    dias_desde_ultima_visita_acs INT64,

    -- Óbito
    obito_indicador BOOL,
    obito_data DATE,

    -- Localização
    area_programatica STRING,
    clinica_nome STRING,
    equipe_nome STRING,
    mudanca_equipe_durante_pn INT64,

    -- Parto
    data_parto DATE,
    tipo_parto STRING,
    estabelecimento_parto STRING,
    motivo_atencimento_parto STRING,
    desfecho_atendimento_parto STRING,

    -- Encaminhamento SISREG
    encaminhado_sisreg STRING,
    sisreg_primeira_data_solicitacao DATE,
    sisreg_primeira_status STRING,
    sisreg_primeira_situacao STRING,
    sisreg_primeira_procedimento_nome STRING,
    sisreg_primeira_procedimento_id STRING,
    sisreg_primeira_unidade_solicitante STRING,
    sisreg_primeira_medico_solicitante STRING,
    sisreg_primeira_operador_solicitante STRING,

    -- Urgência/Emergência
    Urg_Emrg STRING,
    ue_data_consulta DATE,
    ue_motivo_atendimento STRING,
    ue_nome_estabelecimento STRING
)
PARTITION BY data_snapshot
CLUSTER BY id_paciente, fase_atual
OPTIONS(
    description = 'Tabela acumulativa de linha do tempo histórica do pré-natal - apenas snapshots consolidados',
    require_partition_filter = TRUE
);

SELECT '✅ Tabela acumulativa criada/verificada com sucesso' AS log_msg;

-- ============================================================
-- ETAPA 2: PROCESSAR CADA DATA DA LISTA
-- ============================================================

SELECT '========================================' AS log_msg;
SELECT 'ETAPA 2: Processando Datas Individualmente' AS log_msg;
SELECT CONCAT('Total de datas a processar: ', CAST(total_datas AS STRING)) AS log_msg;
SELECT '========================================' AS log_msg;

-- Loop através do array de datas
WHILE indice < total_datas DO
    -- Pegar data atual do array
    SET data_atual = datas_processar[OFFSET(indice)];
    SET inicio_processamento = CURRENT_TIMESTAMP();

    SELECT '----------------------------------------' AS log_msg;
    SELECT CONCAT('📅 Processando data ', CAST(indice + 1 AS STRING), ' de ', CAST(total_datas AS STRING), ': ', CAST(data_atual AS STRING)) AS log_msg;
    SELECT '----------------------------------------' AS log_msg;

    -- ========================================
    -- PROCEDIMENTO 1: Gestações
    -- ========================================
    SELECT CONCAT('  ⏳ [1/6] Executando proced_1_gestacoes_historico...') AS log_msg;
    BEGIN
        CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_atual);
        SELECT '  ✅ [1/6] Procedimento 1 concluído' AS log_msg;
    EXCEPTION WHEN ERROR THEN
        SELECT CONCAT('  ❌ [1/6] ERRO no Procedimento 1 para data ', CAST(data_atual AS STRING)) AS log_msg;
        SELECT @@error.message AS error_message;
        -- Continua para próxima data
        SET indice = indice + 1;
        CONTINUE;
    END;

    -- ========================================
    -- PROCEDIMENTO 2: Atendimentos Pré-Natal APS
    -- ========================================
    SELECT CONCAT('  ⏳ [2/6] Executando proced_2_atd_prenatal_aps_historico...') AS log_msg;
    BEGIN
        CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(data_atual);
        SELECT '  ✅ [2/6] Procedimento 2 concluído' AS log_msg;
    EXCEPTION WHEN ERROR THEN
        SELECT CONCAT('  ❌ [2/6] ERRO no Procedimento 2 para data ', CAST(data_atual AS STRING)) AS log_msg;
        SELECT @@error.message AS error_message;
        SET indice = indice + 1;
        CONTINUE;
    END;

    -- ========================================
    -- PROCEDIMENTO 3: Visitas ACS
    -- ========================================
    SELECT CONCAT('  ⏳ [3/6] Executando proced_3_visitas_acs_gestacao_historico...') AS log_msg;
    BEGIN
        CALL `rj-sms-sandbox.sub_pav_us.proced_3_visitas_acs_gestacao_historico`(data_atual);
        SELECT '  ✅ [3/6] Procedimento 3 concluído' AS log_msg;
    EXCEPTION WHEN ERROR THEN
        SELECT CONCAT('  ❌ [3/6] ERRO no Procedimento 3 para data ', CAST(data_atual AS STRING)) AS log_msg;
        SELECT @@error.message AS error_message;
        SET indice = indice + 1;
        CONTINUE;
    END;

    -- ========================================
    -- PROCEDIMENTO 4: Consultas Emergenciais
    -- ========================================
    SELECT CONCAT('  ⏳ [4/6] Executando proced_4_consultas_emergenciais_historico...') AS log_msg;
    BEGIN
        CALL `rj-sms-sandbox.sub_pav_us.proced_4_consultas_emergenciais_historico`(data_atual);
        SELECT '  ✅ [4/6] Procedimento 4 concluído' AS log_msg;
    EXCEPTION WHEN ERROR THEN
        SELECT CONCAT('  ❌ [4/6] ERRO no Procedimento 4 para data ', CAST(data_atual AS STRING)) AS log_msg;
        SELECT @@error.message AS error_message;
        SET indice = indice + 1;
        CONTINUE;
    END;

    -- ========================================
    -- PROCEDIMENTO 5: Encaminhamentos SISREG
    -- ========================================
    SELECT CONCAT('  ⏳ [5/6] Executando proced_5_encaminhamentos_historico...') AS log_msg;
    BEGIN
        CALL `rj-sms-sandbox.sub_pav_us.proced_5_encaminhamentos_historico`(data_atual);
        SELECT '  ✅ [5/6] Procedimento 5 concluído' AS log_msg;
    EXCEPTION WHEN ERROR THEN
        SELECT CONCAT('  ❌ [5/6] ERRO no Procedimento 5 para data ', CAST(data_atual AS STRING)) AS log_msg;
        SELECT @@error.message AS error_message;
        SET indice = indice + 1;
        CONTINUE;
    END;

    -- ========================================
    -- PROCEDIMENTO 6: Linha do Tempo
    -- ========================================
    SELECT CONCAT('  ⏳ [6/6] Executando proced_6_linha_tempo_historico...') AS log_msg;
    BEGIN
        CALL `rj-sms-sandbox.sub_pav_us.proced_6_linha_tempo_historico`(data_atual);
        SELECT '  ✅ [6/6] Procedimento 6 concluído' AS log_msg;
    EXCEPTION WHEN ERROR THEN
        SELECT CONCAT('  ❌ [6/6] ERRO no Procedimento 6 para data ', CAST(data_atual AS STRING)) AS log_msg;
        SELECT @@error.message AS error_message;
        SET indice = indice + 1;
        CONTINUE;
    END;

    -- ========================================
    -- MATERIALIZAÇÃO: Inserir na tabela acumulativa
    -- ========================================
    SELECT CONCAT('  💾 Materializando tabela 6 na acumulativa...') AS log_msg;
    BEGIN
        INSERT INTO `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
        SELECT * FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
        WHERE data_snapshot = data_atual;

        -- Contar registros inseridos
        SET registros_inseridos = (
            SELECT COUNT(*)
            FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
            WHERE data_snapshot = data_atual
        );

        SET total_registros_acumulados = total_registros_acumulados + registros_inseridos;

        SELECT CONCAT('  ✅ Inseridos ', CAST(registros_inseridos AS STRING), ' registros na tabela acumulativa') AS log_msg;

    EXCEPTION WHEN ERROR THEN
        SELECT CONCAT('  ❌ ERRO ao materializar tabela 6 para data ', CAST(data_atual AS STRING)) AS log_msg;
        SELECT @@error.message AS error_message;
    END;

    -- Calcular duração do processamento
    SET fim_processamento = CURRENT_TIMESTAMP();
    SET duracao_segundos = TIMESTAMP_DIFF(fim_processamento, inicio_processamento, SECOND);

    SELECT CONCAT('  ⏱️  Duração: ', CAST(duracao_segundos AS STRING), ' segundos') AS log_msg;
    SELECT CONCAT('  ✅ Data ', CAST(data_atual AS STRING), ' processada com sucesso!') AS log_msg;

    -- Avançar para próxima data
    SET indice = indice + 1;

END WHILE;

-- ============================================================
-- ETAPA 3: RELATÓRIO FINAL CONSOLIDADO
-- ============================================================

SELECT '========================================' AS log_msg;
SELECT 'ETAPA 3: Relatório Final' AS log_msg;
SELECT '========================================' AS log_msg;

SELECT CONCAT('✅ Processamento Completo!') AS log_msg;
SELECT CONCAT('📊 Total de datas processadas: ', CAST(total_datas AS STRING)) AS log_msg;
SELECT CONCAT('📦 Total de registros acumulados: ', CAST(total_registros_acumulados AS STRING)) AS log_msg;

-- Resumo por data na tabela acumulativa
SELECT '----------------------------------------' AS log_msg;
SELECT 'Resumo de Registros por Data:' AS log_msg;
SELECT '----------------------------------------' AS log_msg;

SELECT
    data_snapshot,
    COUNT(*) AS total_gestacoes,
    COUNT(DISTINCT id_paciente) AS total_pacientes,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(fase_atual = 'Puerpério') AS em_puerperio,
    ROUND(AVG(idade_gestante), 1) AS idade_media,
    COUNTIF(hipertensao_total = 1) AS com_hipertensao,
    COUNTIF(diabetes_total = 1) AS com_diabetes
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
WHERE data_snapshot IN UNNEST(datas_processar)
GROUP BY data_snapshot
ORDER BY data_snapshot;

-- Estatísticas gerais da tabela acumulativa
SELECT '----------------------------------------' AS log_msg;
SELECT 'Estatísticas Gerais da Tabela Acumulativa:' AS log_msg;
SELECT '----------------------------------------' AS log_msg;

SELECT
    COUNT(DISTINCT data_snapshot) AS total_snapshots,
    MIN(data_snapshot) AS snapshot_mais_antigo,
    MAX(data_snapshot) AS snapshot_mais_recente,
    COUNT(*) AS total_registros_geral,
    COUNT(DISTINCT id_paciente) AS total_pacientes_unicos
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`;

SELECT '========================================' AS log_msg;
SELECT '🎉 SCRIPT CONCLUÍDO COM SUCESSO!' AS log_msg;
SELECT '========================================' AS log_msg;
