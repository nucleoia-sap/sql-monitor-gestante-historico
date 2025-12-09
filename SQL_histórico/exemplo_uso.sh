#!/bin/bash

# ============================================================
# EXEMPLO DE USO: construir_historico.sh
# ============================================================
# Este arquivo demonstra diferentes formas de usar o script
# ============================================================

echo "============================================================"
echo "EXEMPLOS DE USO DO SCRIPT construir_historico.sh"
echo "============================================================"
echo ""

# ============================================================
# EXEMPLO 1: Snapshot único (data mais recente)
# ============================================================
echo "1️⃣  SNAPSHOT ÚNICO (última data disponível)"
echo "   ./construir_historico.sh 2024-10-31"
echo ""

# ============================================================
# EXEMPLO 2: Dois snapshots (comparação)
# ============================================================
echo "2️⃣  DOIS SNAPSHOTS (comparação antes/depois)"
echo "   ./construir_historico.sh 2024-07-01 2024-10-31"
echo ""

# ============================================================
# EXEMPLO 3: Série mensal completa (2024)
# ============================================================
echo "3️⃣  SÉRIE MENSAL COMPLETA (12 meses de 2024)"
echo "   ./construir_historico.sh \\"
echo "       2024-01-31 2024-02-29 2024-03-31 \\"
echo "       2024-04-30 2024-05-31 2024-06-30 \\"
echo "       2024-07-31 2024-08-31 2024-09-30 \\"
echo "       2024-10-31 2024-11-30 2024-12-31"
echo ""

# ============================================================
# EXEMPLO 4: Série trimestral
# ============================================================
echo "4️⃣  SÉRIE TRIMESTRAL (último dia de cada trimestre)"
echo "   ./construir_historico.sh \\"
echo "       2024-03-31 2024-06-30 2024-09-30 2024-12-31"
echo ""

# ============================================================
# EXEMPLO 5: Série semanal (1 mês)
# ============================================================
echo "5️⃣  SÉRIE SEMANAL (todas as segundas de outubro/2024)"
echo "   ./construir_historico.sh \\"
echo "       2024-10-07 2024-10-14 2024-10-21 2024-10-28"
echo ""

# ============================================================
# EXEMPLO 6: Datas customizadas (eventos específicos)
# ============================================================
echo "6️⃣  DATAS CUSTOMIZADAS (eventos ou períodos específicos)"
echo "   ./construir_historico.sh \\"
echo "       2024-01-15 2024-04-22 2024-07-10 2024-10-31"
echo ""

# ============================================================
# EXEMPLO PRÁTICO: Executar agora
# ============================================================
echo "============================================================"
echo "💡 EXECUTAR AGORA?"
echo "============================================================"
echo ""
echo "Descomente a linha abaixo para executar o exemplo 1:"
echo ""
echo "# cd \"\$(dirname \"\$0\")\" && ./construir_historico.sh 2024-10-31"
echo ""

# Descomentar para executar automaticamente:
# cd "$(dirname "$0")" && ./construir_historico.sh 2024-10-31
