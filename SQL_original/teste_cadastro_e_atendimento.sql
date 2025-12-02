SELECT

    gest.cpf,
    gest.fase_atual,
    gest.id_paciente,
    gest.nome,
    gest.equipe_nome,
    gest.clinica_nome,
    fa.data_cadastro as cad_data_cadastro,
    fa.situacao_usuario as cad_situacao_usuario,
    fa.cadastro_permanente as cad_cadastro_permanente,
    fa.ap_cadastro as cad_ap_cadastro,
    fa.codigo_equipe as cad_codigo_equipe,
    fa.cpf as cad_cpf,
    fa.equipe_nome as cad_equipe_nome,
    fa.ine_equipe as cad_ine_equipe,
    fa.microarea as cad_microarea,
    fa.numero_prontuario as cad_numero_prontuario,
    fa.unidade_cadastro as cad_unidade_cadastro,
    fa.unidade_nome as cad_unidade_nome

-- FROM {{ ref('mart_historico_clinico__paciente') }}
from rj-sms.projeto_gestacoes.gestacoes gest
LEFT JOIN (
    SELECT *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY id_paciente
                ORDER BY
                    CASE WHEN cadastro_permanente = true THEN 0 ELSE 1 END,
                    data_cadastro DESC
            ) as rn
        FROM rj-sms.brutos_prontuario_vitacare.ficha_a
        WHERE LOWER(TRIM(CAST(situacao_usuario AS STRING))) = 'ativo'
    )
    WHERE rn = 1
) fa
ON gest.id_paciente = fa.id_paciente
where fase_atual = 'Gestação'
order by gest.nome
limit 1000