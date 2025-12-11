#!/bin/bash

# ============================================================
# Script para Construir Histórico de Gestações
# ============================================================
# Executa os 3 scripts SQL na ordem correta para cada data
# especificada, usando BigQuery CLI (bq)
#
# ORDEM DE EXECUÇÃO:
# 1. _hist_1_gestacoes.sql         → Tabela _gestacoes_historico
# 2. _hist_2_atd_prenatal_aps.sql  → Tabela _atendimentos_prenatal_aps_historico
# 3. _hist_6_linha_tempo.sql       → Tabela _linha_tempo_historico
#
# USO:
# ./construir_historico.sh 2024-07-01 2024-08-01 2024-09-01
# ou edite a variável DATAS_PROCESSAR abaixo
# ============================================================

set -e  # Para execução ao encontrar erro

# ============================================================
# CONFIGURAÇÃO: Defina as datas aqui
# ============================================================
# Formato: YYYY-MM-DD separado por espaços
# Deixe vazio para usar as datas passadas como argumentos
DATAS_PROCESSAR=(
    "2024-01-01"
    "2024-02-01"
    "2024-03-01"
    "2024-04-01"
    "2024-05-01"
    "2024-06-01"
    "2024-07-01"
    "2024-08-01"
    "2024-09-01"
    "2024-10-01"
    "2024-11-01"
    "2024-12-01"
)

# ============================================================
# Configuração do projeto
# ============================================================
PROJETO="rj-sms-sandbox"
DATASET="sub_pav_us"

# Diretório dos scripts SQL (diretório atual do script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# Verificações iniciais
# ============================================================
echo "============================================================"
echo "Script de Construção de Histórico de Gestações"
echo "============================================================"
echo ""

# Verificar se bq está instalado
if ! command -v bq &> /dev/null; then
    echo "❌ ERRO: BigQuery CLI (bq) não encontrado!"
    echo "   Instale com: gcloud components install bq"
    exit 1
fi

# Verificar autenticação
if ! bq ls --project_id="$PROJETO" &> /dev/null; then
    echo "❌ ERRO: Não autenticado no projeto $PROJETO"
    echo "   Execute: gcloud auth login"
    exit 1
fi

echo "✅ BigQuery CLI encontrado"
echo "✅ Autenticado no projeto: $PROJETO"
echo ""

# ============================================================
# Processar datas
# ============================================================

# Se não há datas configuradas no array, usar argumentos da linha de comando
if [ ${#DATAS_PROCESSAR[@]} -eq 0 ]; then
    if [ $# -eq 0 ]; then
        echo "❌ ERRO: Nenhuma data especificada!"
        echo ""
        echo "USO:"
        echo "  1. Passar datas como argumentos:"
        echo "     ./construir_historico.sh 2024-07-01 2024-08-01"
        echo ""
        echo "  2. Editar o array DATAS_PROCESSAR no início do script"
        echo ""
        exit 1
    fi
    DATAS_PROCESSAR=("$@")
fi

echo "📅 Datas a processar: ${DATAS_PROCESSAR[*]}"
echo "📊 Total: ${#DATAS_PROCESSAR[@]} data(s)"
echo ""

# ============================================================
# Função para executar SQL com substituição de data
# ============================================================
executar_sql() {
    local sql_file="$1"
    local data_ref="$2"
    local descricao="$3"

    echo "   ⏳ $descricao..."

    # Criar arquivo temporário com a data substituída
    local temp_file=$(mktemp)

    # Substituir a linha DECLARE data_referencia
    sed "s/DECLARE data_referencia DATE DEFAULT DATE('[0-9\-]*');/DECLARE data_referencia DATE DEFAULT DATE('$data_ref');/" \
        "$sql_file" > "$temp_file"

    # Executar via bq
    if bq query \
        --project_id="$PROJETO" \
        --use_legacy_sql=false \
        --max_rows=0 \
        < "$temp_file" 2>&1 | grep -v "^Waiting on"; then

        echo "   ✅ $descricao concluído"
        rm "$temp_file"
        return 0
    else
        echo "   ❌ ERRO em $descricao"
        rm "$temp_file"
        return 1
    fi
}

# ============================================================
# Função para gerar JSON do dashboard
# ============================================================
gerar_json_dashboard() {
    echo "============================================================"
    echo "📊 Gerando JSON do Dashboard"
    echo "============================================================"
    echo ""
    echo "⏳ Executando query de agregação..."

    # Caminho para a query do dashboard (diretório pai)
    local query_dashboard="$SCRIPT_DIR/../query_dashboard_completo_clean.sql"
    local json_output="$SCRIPT_DIR/../dashboard_data_completo.json"

    if [ ! -f "$query_dashboard" ]; then
        echo "⚠️  AVISO: Arquivo query_dashboard_completo_clean.sql não encontrado"
        echo "   Esperado em: $query_dashboard"
        return 1
    fi

    # Executar query e salvar como JSON
    if bq query \
        --project_id="$PROJETO" \
        --use_legacy_sql=false \
        --format=json \
        < "$query_dashboard" > "$json_output" 2>&1; then

        # Contar snapshots no JSON
        local num_snapshots=$(grep -o '"data_snapshot"' "$json_output" | wc -l | tr -d ' ')

        echo "✅ JSON gerado com sucesso!"
        echo "📁 Arquivo: dashboard_data_completo.json"
        echo "📊 Snapshots incluídos: $num_snapshots"
        echo ""
        echo "💡 Para visualizar, abra o arquivo dashboard_prescricoes_v2.html no navegador"
        return 0
    else
        echo "❌ ERRO ao gerar JSON do dashboard"
        return 1
    fi
}

# ============================================================
# Processar cada data
# ============================================================
SUCESSO=0
FALHAS=0
INICIO_TOTAL=$(date +%s)

for DATA in "${DATAS_PROCESSAR[@]}"; do
    echo "============================================================"
    echo "📆 Processando data: $DATA"
    echo "============================================================"

    INICIO_DATA=$(date +%s)

    # Validar formato da data
    if ! date -d "$DATA" &> /dev/null 2>&1 && ! date -j -f "%Y-%m-%d" "$DATA" &> /dev/null 2>&1; then
        echo "   ❌ Data inválida: $DATA (formato esperado: YYYY-MM-DD)"
        echo ""
        ((FALHAS++))
        continue
    fi

    # Executar os 3 scripts na ordem
    if executar_sql "$SCRIPT_DIR/_hist_1_gestacoes.sql" "$DATA" "1/3 Gestações" && \
       executar_sql "$SCRIPT_DIR/_hist_2_atd_prenatal_aps.sql" "$DATA" "2/3 Atendimentos Pré-Natal" && \
       executar_sql "$SCRIPT_DIR/_hist_6_linha_tempo.sql" "$DATA" "3/3 Linha do Tempo"; then

        FIM_DATA=$(date +%s)
        DURACAO=$((FIM_DATA - INICIO_DATA))

        echo ""
        echo "   ✅ Snapshot $DATA concluído com sucesso!"
        echo "   ⏱️  Tempo: ${DURACAO}s"
        ((SUCESSO++))
    else
        echo ""
        echo "   ❌ Falha no processamento de $DATA"
        ((FALHAS++))
    fi

    echo ""
done

# ============================================================
# Relatório Final
# ============================================================
FIM_TOTAL=$(date +%s)
DURACAO_TOTAL=$((FIM_TOTAL - INICIO_TOTAL))

echo "============================================================"
echo "📊 RELATÓRIO FINAL"
echo "============================================================"
echo "✅ Sucessos: $SUCESSO"
echo "❌ Falhas: $FALHAS"
echo "⏱️  Tempo total: ${DURACAO_TOTAL}s"
echo ""

if [ $FALHAS -eq 0 ]; then
    echo "🎉 Processamento dos snapshots concluído com sucesso!"
    echo ""

    # Gerar JSON do dashboard automaticamente
    if gerar_json_dashboard; then
        echo ""
        echo "============================================================"
        echo "✅ PIPELINE COMPLETO EXECUTADO COM SUCESSO!"
        echo "============================================================"
        echo ""
        echo "📊 Dados processados:"
        echo "   - ${SUCESSO} snapshot(s) histórico(s)"
        echo "   - JSON do dashboard atualizado"
        echo ""
        echo "🌐 PRÓXIMOS PASSOS:"
        echo "1. Abra o dashboard no navegador:"
        echo "   http://localhost:8000/dashboard_prescricoes_v2.html"
        echo ""
        echo "2. Se necessário, inicie o servidor HTTP:"
        echo "   python3 -m http.server 8000"
        echo ""
        echo "3. Verifique os dados nas tabelas BigQuery:"
        echo "   - ${PROJETO}.${DATASET}._gestacoes_historico"
        echo "   - ${PROJETO}.${DATASET}._atendimentos_prenatal_aps_historico"
        echo "   - ${PROJETO}.${DATASET}._linha_tempo_historico"
        echo ""
        exit 0
    else
        echo ""
        echo "⚠️  Snapshots processados, mas houve erro ao gerar JSON do dashboard"
        echo "   Execute manualmente:"
        echo "   bq query --format=json --use_legacy_sql=false < ../query_dashboard_completo_clean.sql > ../dashboard_data_completo.json"
        echo ""
        exit 1
    fi
else
    echo "⚠️  Processamento concluído com falhas!"
    echo "   Revise os erros acima"
    echo ""
    exit 1
fi
