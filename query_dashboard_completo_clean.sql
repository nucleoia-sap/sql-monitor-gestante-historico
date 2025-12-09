SELECT
    data_snapshot,
    COUNT(*) AS total_gestantes_ativas,
    COUNTIF(prescricao_acido_folico = 'sim') AS gestantes_acido_folico,
    ROUND(COUNTIF(prescricao_acido_folico = 'sim') * 100.0 / COUNT(*), 2) AS perc_acido_folico,
    COUNTIF(prescricao_carbonato_calcio = 'sim') AS gestantes_carbonato_calcio,
    ROUND(COUNTIF(prescricao_carbonato_calcio = 'sim') * 100.0 / COUNT(*), 2) AS perc_carbonato_calcio,
    COUNTIF(hipertensao_total = 1) AS gestantes_hipertensao,
    ROUND(COUNTIF(hipertensao_total = 1) * 100.0 / COUNT(*), 2) AS perc_hipertensao,
    COUNTIF(diabetes_total = 1) AS gestantes_diabetes,
    ROUND(COUNTIF(diabetes_total = 1) * 100.0 / COUNT(*), 2) AS perc_diabetes,
    COUNTIF(sifilis = 1) AS gestantes_sifilis,
    ROUND(COUNTIF(sifilis = 1) * 100.0 / COUNT(*), 2) AS perc_sifilis,
    COUNTIF(hipertensao_total = 1 AND tem_anti_hipertensivo = 1) AS hipertensas_com_medicacao,
    ROUND(COUNTIF(hipertensao_total = 1 AND tem_anti_hipertensivo = 1) * 100.0 / NULLIF(COUNTIF(hipertensao_total = 1), 0), 2) AS perc_hipertensas_medicadas,
    COUNTIF(diabetes_total = 1 AND tem_antidiabetico = 1) AS diabeticas_com_medicacao,
    ROUND(COUNTIF(diabetes_total = 1 AND tem_antidiabetico = 1) * 100.0 / NULLIF(COUNTIF(diabetes_total = 1), 0), 2) AS perc_diabeticas_medicadas
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'
GROUP BY data_snapshot
ORDER BY data_snapshot DESC;
