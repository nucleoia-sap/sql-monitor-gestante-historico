-- ============================================================
-- Script de Teste: Procedimentos 3, 4, 5 e 6
-- ============================================================
-- Este script testa os procedimentos 3 a 6 do pipeline histórico
-- Pré-requisito: Procedimentos 1 e 2 já executados com sucesso
--
-- INSTRUÇÕES:
-- 1. Copie este script completo
-- 2. Execute no BigQuery console
-- 3. Verifique os resultados de cada validação
-- ============================================================

-- Data de referência para teste (mesmo valor usado nos testes anteriores)
DECLARE data_ref DATE DEFAULT DATE('2024-10-31');

-- ============================================================
-- PRÉ-VALIDAÇÃO: Verificar se procedimentos 1 e 2 foram executados
-- ============================================================
SELECT 'PRE-VALIDACAO' AS etapa, '1. Verificando dependências' AS acao;

SELECT
    'Gestações disponíveis' AS verificacao,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = data_ref;

-- Se retornar 0 registros, PARE AQUI e execute os procedimentos 1 e 2 primeiro!

-- ============================================================
-- PROCEDIMENTO 3: Visitas ACS
-- ============================================================
SELECT 'TESTE PROCEDIMENTO 3' AS etapa, 'Executando proced_3_visitas_acs_gestacao_historico' AS acao;

CALL `rj-sms-sandbox.sub_pav_us.proced_3_visitas_acs_gestacao_historico`(data_ref);

-- Validação Procedimento 3
SELECT
    '3. Validação Visitas ACS' AS validacao,
    COUNT(*) AS total_visitas,
    COUNT(DISTINCT id_gestacao) AS gestacoes_com_visita,
    COUNT(DISTINCT id_paciente) AS pacientes_com_visita,
    MIN(entrada_data) AS primeira_visita,
    MAX(entrada_data) AS ultima_visita,
    ROUND(AVG(numero_visita), 2) AS media_visitas_por_gestacao
FROM `rj-sms-sandbox.sub_pav_us._visitas_acs_gestacao_historico`
WHERE data_snapshot = data_ref;

-- Distribuição de visitas por gestação
SELECT
    '3. Distribuição de Visitas' AS analise,
    numero_visita,
    COUNT(DISTINCT id_gestacao) AS total_gestacoes
FROM `rj-sms-sandbox.sub_pav_us._visitas_acs_gestacao_historico`
WHERE data_snapshot = data_ref
GROUP BY numero_visita
ORDER BY numero_visita;

-- ============================================================
-- PROCEDIMENTO 4: Consultas Emergenciais
-- ============================================================
SELECT 'TESTE PROCEDIMENTO 4' AS etapa, 'Executando proced_4_consultas_emergenciais_historico' AS acao;

CALL `rj-sms-sandbox.sub_pav_us.proced_4_consultas_emergenciais_historico`(data_ref);

-- Validação Procedimento 4
SELECT
    '4. Validação Consultas Emergenciais' AS validacao,
    COUNT(*) AS total_consultas_emergencia,
    COUNT(DISTINCT id_gestacao) AS gestacoes_com_emergencia,
    COUNT(DISTINCT id_paciente) AS pacientes_com_emergencia,
    MIN(data_consulta) AS primeira_consulta,
    MAX(data_consulta) AS ultima_consulta,
    ROUND(AVG(idade_gestacional_consulta), 2) AS media_ig_semanas
FROM `rj-sms-sandbox.sub_pav_us._consultas_emergenciais_historico`
WHERE data_snapshot = data_ref;

-- Principais motivos de emergência
SELECT
    '4. Motivos de Emergência' AS analise,
    motivo_atendimento,
    COUNT(*) AS total_atendimentos
FROM `rj-sms-sandbox.sub_pav_us._consultas_emergenciais_historico`
WHERE data_snapshot = data_ref
  AND motivo_atendimento IS NOT NULL
GROUP BY motivo_atendimento
ORDER BY total_atendimentos DESC
LIMIT 10;

-- Principais CIDs de emergência
SELECT
    '4. CIDs Emergenciais' AS analise,
    cids_emergencia,
    COUNT(*) AS total_ocorrencias
FROM `rj-sms-sandbox.sub_pav_us._consultas_emergenciais_historico`
WHERE data_snapshot = data_ref
  AND cids_emergencia IS NOT NULL
GROUP BY cids_emergencia
ORDER BY total_ocorrencias DESC
LIMIT 10;

-- ============================================================
-- PROCEDIMENTO 5: Encaminhamentos SISREG
-- ============================================================
SELECT 'TESTE PROCEDIMENTO 5' AS etapa, 'Executando proced_5_encaminhamentos_historico' AS acao;

CALL `rj-sms-sandbox.sub_pav_us.proced_5_encaminhamentos_historico`(data_ref);

-- Validação Procedimento 5
SELECT
    '5. Validação Encaminhamentos SISREG' AS validacao,
    COUNT(*) AS total_encaminhamentos,
    COUNT(DISTINCT id_gestacao) AS gestacoes_com_encaminhamento,
    COUNT(DISTINCT id_paciente) AS pacientes_encaminhadas,
    MIN(sisreg_primeira_data_solicitacao_data) AS primeira_solicitacao,
    MAX(sisreg_primeira_data_solicitacao_data) AS ultima_solicitacao
FROM `rj-sms-sandbox.sub_pav_us._encaminhamentos_historico`
WHERE data_snapshot = data_ref;

-- Distribuição por status de solicitação
SELECT
    '5. Status Encaminhamentos' AS analise,
    sisreg_primeira_status,
    COUNT(*) AS total_solicitacoes
FROM `rj-sms-sandbox.sub_pav_us._encaminhamentos_historico`
WHERE data_snapshot = data_ref
  AND sisreg_primeira_status IS NOT NULL
GROUP BY sisreg_primeira_status
ORDER BY total_solicitacoes DESC;

-- Principais procedimentos solicitados
SELECT
    '5. Procedimentos Solicitados' AS analise,
    sisreg_primeira_procedimento_nome,
    sisreg_primeira_procedimento_id,
    COUNT(*) AS total_solicitacoes
FROM `rj-sms-sandbox.sub_pav_us._encaminhamentos_historico`
WHERE data_snapshot = data_ref
  AND sisreg_primeira_procedimento_nome IS NOT NULL
GROUP BY sisreg_primeira_procedimento_nome, sisreg_primeira_procedimento_id
ORDER BY total_solicitacoes DESC;

-- ============================================================
-- PROCEDIMENTO 6: Linha do Tempo (Agregação Final)
-- ============================================================
SELECT 'TESTE PROCEDIMENTO 6' AS etapa, 'Executando proced_6_linha_tempo_historico' AS acao;

CALL `rj-sms-sandbox.sub_pav_us.proced_6_linha_tempo_historico`(data_ref);

-- Validação Procedimento 6 - Visão Geral
SELECT
    '6. Validação Linha do Tempo' AS validacao,
    COUNT(*) AS total_gestacoes_linha_tempo,
    COUNT(DISTINCT id_paciente) AS total_pacientes_unicos,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(fase_atual = 'Puerpério') AS em_puerperio,
    ROUND(AVG(idade_gestante), 2) AS idade_media,
    ROUND(AVG(qtd_consultas_realizadas), 2) AS media_consultas
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_ref;

-- Indicadores de Cobertura
SELECT
    '6. Indicadores de Cobertura' AS analise,
    COUNTIF(tem_primeira_consulta_primeiro_trimestre = 1) AS consulta_1tri,
    COUNTIF(qtd_consultas_realizadas >= 6) AS adequacao_6_consultas,
    COUNTIF(qtd_visitas_acs >= 1) AS com_visita_acs,
    ROUND(100.0 * COUNTIF(tem_primeira_consulta_primeiro_trimestre = 1) / NULLIF(COUNT(*), 0), 2) AS perc_consulta_1tri,
    ROUND(100.0 * COUNTIF(qtd_consultas_realizadas >= 6) / NULLIF(COUNT(*), 0), 2) AS perc_adequacao_6_consultas,
    ROUND(100.0 * COUNTIF(qtd_visitas_acs >= 1) / NULLIF(COUNT(*), 0), 2) AS perc_com_visita_acs
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_ref
  AND fase_atual = 'Gestação';

-- Indicadores Clínicos - Hipertensão
SELECT
    '6. Indicadores - Hipertensão' AS analise,
    COUNTIF(hipertensao_total = 1) AS gestantes_com_hipertensao,
    COUNTIF(hipertensao_previa = 1) AS hipertensao_previa,
    COUNTIF(hipertensao_gestacional = 1) AS hipertensao_gestacional,
    COUNTIF(tem_anti_hipertensivo = 1) AS com_medicacao,
    COUNTIF(tem_encaminhamento_has = 1) AS encaminhadas_alto_risco,
    ROUND(100.0 * COUNTIF(hipertensao_total = 1) / NULLIF(COUNT(*), 0), 2) AS prevalencia_has
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_ref
  AND fase_atual = 'Gestação';

-- Indicadores Clínicos - Diabetes
SELECT
    '6. Indicadores - Diabetes' AS analise,
    COUNTIF(diabetes_total = 1) AS gestantes_com_diabetes,
    COUNTIF(diabetes_previa = 1) AS diabetes_previa,
    COUNTIF(diabetes_gestacional = 1) AS diabetes_gestacional,
    COUNTIF(tem_antidiabetico = 1) AS com_medicacao,
    ROUND(100.0 * COUNTIF(diabetes_total = 1) / NULLIF(COUNT(*), 0), 2) AS prevalencia_diabetes
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_ref
  AND fase_atual = 'Gestação';

-- Indicadores de Tratamento
SELECT
    '6. Indicadores - Tratamento' AS analise,
    COUNTIF(tem_sulfato_ferroso = 1) AS com_sulfato_ferroso,
    COUNTIF(tem_acido_folico = 1) AS com_acido_folico,
    COUNTIF(adequacao_aas = 'Adequada') AS adequacao_aas_adequada,
    ROUND(100.0 * COUNTIF(tem_sulfato_ferroso = 1) / NULLIF(COUNT(*), 0), 2) AS perc_sulfato_ferroso,
    ROUND(100.0 * COUNTIF(tem_acido_folico = 1) / NULLIF(COUNT(*), 0), 2) AS perc_acido_folico
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_ref
  AND fase_atual = 'Gestação';

-- Distribuição por Área Programática
SELECT
    '6. Distribuição por AP' AS analise,
    area_programatica,
    COUNT(*) AS total_gestacoes,
    ROUND(AVG(qtd_consultas_realizadas), 2) AS media_consultas,
    ROUND(100.0 * COUNTIF(qtd_consultas_realizadas >= 6) / NULLIF(COUNT(*), 0), 2) AS perc_adequacao
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_ref
  AND fase_atual = 'Gestação'
GROUP BY area_programatica
ORDER BY total_gestacoes DESC;

-- ============================================================
-- VALIDAÇÃO DE CONSISTÊNCIA ENTRE TABELAS
-- ============================================================
SELECT 'VALIDACAO CONSISTENCIA' AS etapa, 'Verificando integridade referencial' AS acao;

-- Verificar se todas as gestações da linha do tempo existem nas tabelas base
WITH gestacoes_linha_tempo AS (
    SELECT DISTINCT id_gestacao
    FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
    WHERE data_snapshot = data_ref
),
gestacoes_base AS (
    SELECT DISTINCT id_gestacao
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    WHERE data_snapshot = data_ref
)
SELECT
    'Consistência Gestações' AS verificacao,
    (SELECT COUNT(*) FROM gestacoes_linha_tempo) AS total_linha_tempo,
    (SELECT COUNT(*) FROM gestacoes_base) AS total_gestacoes_base,
    (SELECT COUNT(*) FROM gestacoes_linha_tempo WHERE id_gestacao NOT IN (SELECT id_gestacao FROM gestacoes_base)) AS gestacoes_orfas;

-- Verificar consistência de contadores
SELECT
    'Consistência Contadores' AS verificacao,
    lt.id_gestacao,
    lt.qtd_consultas_realizadas AS contador_linha_tempo,
    COUNT(DISTINCT atd.data_consulta) AS consultas_reais,
    lt.qtd_visitas_acs AS visitas_contador,
    COUNT(DISTINCT vis.entrada_data) AS visitas_reais,
    lt.qtd_consultas_emergenciais AS emergencias_contador,
    COUNT(DISTINCT eme.data_consulta) AS emergencias_reais
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico` lt
LEFT JOIN `rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico` atd
    ON lt.id_gestacao = atd.id_gestacao
    AND atd.data_snapshot = data_ref
LEFT JOIN `rj-sms-sandbox.sub_pav_us._visitas_acs_gestacao_historico` vis
    ON lt.id_gestacao = vis.id_gestacao
    AND vis.data_snapshot = data_ref
LEFT JOIN `rj-sms-sandbox.sub_pav_us._consultas_emergenciais_historico` eme
    ON lt.id_gestacao = eme.id_gestacao
    AND eme.data_snapshot = data_ref
WHERE lt.data_snapshot = data_ref
GROUP BY lt.id_gestacao, lt.qtd_consultas_realizadas, lt.qtd_visitas_acs, lt.qtd_consultas_emergenciais
HAVING
    lt.qtd_consultas_realizadas != COUNT(DISTINCT atd.data_consulta)
    OR lt.qtd_visitas_acs != COUNT(DISTINCT vis.entrada_data)
    OR lt.qtd_consultas_emergenciais != COUNT(DISTINCT eme.data_consulta)
LIMIT 10;

-- ============================================================
-- RESUMO FINAL DE TODOS OS PROCEDIMENTOS
-- ============================================================
SELECT 'RESUMO FINAL' AS etapa, 'Visão consolidada de todas as tabelas' AS acao;

SELECT
    '1. Gestações' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes,
    MIN(data_inicio) AS data_inicio_min,
    MAX(data_inicio) AS data_inicio_max
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = data_ref

UNION ALL

SELECT
    '2. Atendimentos PN APS' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes,
    MIN(data_consulta) AS data_min,
    MAX(data_consulta) AS data_max
FROM `rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico`
WHERE data_snapshot = data_ref

UNION ALL

SELECT
    '3. Visitas ACS' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes,
    MIN(entrada_data) AS data_min,
    MAX(entrada_data) AS data_max
FROM `rj-sms-sandbox.sub_pav_us._visitas_acs_gestacao_historico`
WHERE data_snapshot = data_ref

UNION ALL

SELECT
    '4. Consultas Emergenciais' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes,
    MIN(data_consulta) AS data_min,
    MAX(data_consulta) AS data_max
FROM `rj-sms-sandbox.sub_pav_us._consultas_emergenciais_historico`
WHERE data_snapshot = data_ref

UNION ALL

SELECT
    '5. Encaminhamentos' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes,
    MIN(sisreg_primeira_data_solicitacao_data) AS data_min,
    MAX(sisreg_primeira_data_solicitacao_data) AS data_max
FROM `rj-sms-sandbox.sub_pav_us._encaminhamentos_historico`
WHERE data_snapshot = data_ref

UNION ALL

SELECT
    '6. Linha do Tempo' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes,
    MIN(data_inicio) AS data_min,
    MAX(data_inicio) AS data_max
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_ref

ORDER BY tabela;

-- ============================================================
-- FIM DO TESTE
-- ============================================================
SELECT
    '✅ TESTE COMPLETO' AS resultado,
    'Todos os procedimentos 3, 4, 5 e 6 foram executados e validados' AS mensagem,
    data_ref AS data_snapshot_testada;
