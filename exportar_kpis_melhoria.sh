#!/bin/bash
# ============================================================
# Script para exportar KPIs de Melhoria do BigQuery para JSON
# ============================================================
# Uso: ./exportar_kpis_melhoria.sh
# Saída: kpis_melhoria_data.json
# ============================================================

set -e

OUTPUT_FILE="kpis_melhoria_data.json"

echo "=============================================="
echo "Exportando KPIs de Melhoria - Gestantes"
echo "=============================================="

# Query SQL para extrair os KPIs
SQL_QUERY='
SELECT
    data_snapshot,
    COUNT(*) AS total_gestantes,
    
    -- KPI 1: AAS
    COUNTIF(tem_indicacao_aas = 1) AS total_com_indicacao_aas,
    COUNTIF(tem_indicacao_aas = 1 AND COALESCE(tem_prescricao_aas, 0) = 0) AS aas_indicado_sem_prescricao,
    ROUND(SAFE_DIVIDE(
        COUNTIF(tem_indicacao_aas = 1 AND COALESCE(tem_prescricao_aas, 0) = 0),
        COUNTIF(tem_indicacao_aas = 1)
    ) * 100, 1) AS pct_aas_indicado_sem_prescricao,
    
    -- KPI 2: Encaminhamento
    COUNTIF(deve_encaminhar IS NOT NULL AND TRIM(deve_encaminhar) != "") AS total_deve_encaminhar,
    COUNTIF(
        deve_encaminhar IS NOT NULL 
        AND TRIM(deve_encaminhar) != "" 
        AND (houve_encaminhamento IS NULL OR houve_encaminhamento != "Sim")
    ) AS alto_risco_sem_encaminhamento,
    ROUND(SAFE_DIVIDE(
        COUNTIF(
            deve_encaminhar IS NOT NULL 
            AND TRIM(deve_encaminhar) != "" 
            AND (houve_encaminhamento IS NULL OR houve_encaminhamento != "Sim")
        ),
        COUNTIF(deve_encaminhar IS NOT NULL AND TRIM(deve_encaminhar) != "")
    ) * 100, 1) AS pct_alto_risco_sem_encaminhamento,
    
    -- KPI 3: Sífilis (apenas contagem por enquanto)
    COUNTIF(sifilis = 1) AS total_com_sifilis,
    
    -- KPI 4: 30 dias sem consulta
    COUNTIF(mais_de_30_sem_atd = "sim") AS mais_30_dias_sem_consulta,
    ROUND(COUNTIF(mais_de_30_sem_atd = "sim") * 100.0 / COUNT(*), 1) AS pct_mais_30_dias_sem_consulta,
    
    -- KPI 5: Carbonato de cálcio
    COUNTIF(prescricao_carbonato_calcio = "não" OR prescricao_carbonato_calcio IS NULL) AS sem_carbonato_calcio,
    ROUND(COUNTIF(prescricao_carbonato_calcio = "não" OR prescricao_carbonato_calcio IS NULL) * 100.0 / COUNT(*), 1) AS pct_sem_carbonato_calcio,
    
    -- KPI 6: Ácido fólico
    COUNTIF(prescricao_acido_folico = "não" OR prescricao_acido_folico IS NULL) AS sem_acido_folico,
    ROUND(COUNTIF(prescricao_acido_folico = "não" OR prescricao_acido_folico IS NULL) * 100.0 / COUNT(*), 1) AS pct_sem_acido_folico

FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = "Gestação"
GROUP BY data_snapshot
ORDER BY data_snapshot
'

echo "Executando query no BigQuery..."

# Executar query e salvar como JSON
bq query \
    --use_legacy_sql=false \
    --format=prettyjson \
    "$SQL_QUERY" > "$OUTPUT_FILE"

echo ""
echo "Dados exportados para: $OUTPUT_FILE"
echo ""

# Mostrar preview dos dados
echo "Preview dos dados:"
head -50 "$OUTPUT_FILE"

echo ""
echo "=============================================="
echo "Exportação concluída!"
echo "=============================================="
