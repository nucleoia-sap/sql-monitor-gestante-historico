#!/bin/bash

# ============================================================
# Script para Publicar SQL_histórico/ no GitHub
# ============================================================
# Automatiza o processo de adicionar arquivos ao repositório
# e fazer push para o branch 1_gestacoes_historico
#
# USO:
# chmod +x publicar_github.sh
# ./publicar_github.sh
# ============================================================

set -e  # Para execução ao encontrar erro

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ============================================================
# Funções auxiliares
# ============================================================

print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# ============================================================
# Verificações iniciais
# ============================================================

print_step "Verificando ambiente..."

# Verificar se estamos no diretório correto
if [ ! -d "SQL_histórico" ]; then
    print_error "Diretório SQL_histórico não encontrado!"
    echo "Execute este script no diretório raiz do projeto."
    exit 1
fi

# Verificar se git está instalado
if ! command -v git &> /dev/null; then
    print_error "Git não está instalado!"
    exit 1
fi

# Verificar se estamos em um repositório git
if [ ! -d ".git" ]; then
    print_error "Não estamos em um repositório git!"
    exit 1
fi

print_success "Ambiente verificado"

# ============================================================
# Status inicial
# ============================================================

print_step "Status atual do repositório:"
git branch --show-current
echo ""

print_step "Arquivos modificados:"
git status --short
echo ""

# ============================================================
# Confirmar com usuário
# ============================================================

echo -e "${YELLOW}Este script irá:${NC}"
echo "1. Adicionar todos os arquivos do SQL_histórico/"
echo "2. Adicionar novas documentações"
echo "3. Registrar deleções de arquivos antigos"
echo "4. Criar commit com mensagem padronizada"
echo "5. Fazer push para origin/1_gestacoes_historico"
echo ""

read -p "Deseja continuar? (s/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[SsYy]$ ]]; then
    print_warning "Operação cancelada pelo usuário"
    exit 0
fi

# ============================================================
# Adicionar arquivos
# ============================================================

print_step "Adicionando arquivos do SQL_histórico/..."

git add "SQL_histórico/_hist_1_gestacoes.sql"
git add "SQL_histórico/_hist_2_atd_prenatal_aps.sql"
git add "SQL_histórico/_hist_6_linha_tempo.sql"
git add "SQL_histórico/construir_historico.sh"
git add "SQL_histórico/exemplo_uso.sh"
git add "SQL_histórico/QUICK_START.md"
git add "SQL_histórico/README.md"
git add "SQL_histórico/README_CONSTRUIR_HISTORICO.md"

print_success "Arquivos SQL_histórico/ adicionados"

# ============================================================
# Adicionar documentações
# ============================================================

print_step "Adicionando documentações novas..."

# Verificar existência antes de adicionar
[ -f "README_DASHBOARD.md" ] && git add "README_DASHBOARD.md"
[ -f "README_EVOLUCAO_HISTORICA.md" ] && git add "README_EVOLUCAO_HISTORICA.md"
[ -f "README_VALIDACAO_GESTACOES.md" ] && git add "README_VALIDACAO_GESTACOES.md"
[ -f "RELATORIO_CORRECAO_DESFECHO.md" ] && git add "RELATORIO_CORRECAO_DESFECHO.md"
[ -f "EXPLICACAO_GESTACOES_HISTORICO.md" ] && git add "EXPLICACAO_GESTACOES_HISTORICO.md"
[ -f "GUIA_PUBLICACAO_GITHUB.md" ] && git add "GUIA_PUBLICACAO_GITHUB.md"

print_success "Documentações adicionadas"

# ============================================================
# Adicionar scripts e dashboard
# ============================================================

print_step "Adicionando scripts e dashboard..."

[ -f "validacao_gestacoes_historico.sql" ] && git add "validacao_gestacoes_historico.sql"
[ -f "query_dashboard_completo_clean.sql" ] && git add "query_dashboard_completo_clean.sql"
[ -f "analise_prescricoes_condicoes.sql" ] && git add "analise_prescricoes_condicoes.sql"
[ -f "dashboard_prescricoes_v2.html" ] && git add "dashboard_prescricoes_v2.html"
[ -f "dashboard_data_completo.json" ] && git add "dashboard_data_completo.json"

print_success "Scripts e dashboard adicionados"

# ============================================================
# Registrar deleções
# ============================================================

print_step "Registrando deleções de arquivos antigos..."

git add -u

print_success "Deleções registradas"

# ============================================================
# Verificar mudanças
# ============================================================

print_step "Mudanças preparadas para commit:"
echo ""
git status --short
echo ""

read -p "As mudanças estão corretas? (s/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[SsYy]$ ]]; then
    print_warning "Operação cancelada. Use 'git reset' para desfazer as adições."
    exit 0
fi

# ============================================================
# Criar commit
# ============================================================

print_step "Criando commit..."

git commit -m "feat: Add SQL_histórico directory with automated snapshot scripts

- Add 3 historical SQL scripts (_hist_1_gestacoes, _hist_2_atd_prenatal_aps, _hist_6_linha_tempo)
- Add construir_historico.sh automated execution script
- Add comprehensive documentation (QUICK_START, README_CONSTRUIR_HISTORICO)
- Add dashboard visualization (dashboard_prescricoes_v2.html)
- Update typical record counts to ~28,000 pregnancies per snapshot


if [ $? -eq 0 ]; then
    print_success "Commit criado com sucesso"
else
    print_error "Falha ao criar commit"
    exit 1
fi

# ============================================================
# Push para GitHub
# ============================================================

print_step "Fazendo push para origin/1_gestacoes_historico..."

echo -e "${YELLOW}⚠️  Último aviso antes do push!${NC}"
read -p "Confirma push para GitHub? (s/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[SsYy]$ ]]; then
    print_warning "Push cancelado. O commit local foi criado."
    print_warning "Para fazer push manualmente: git push origin 1_gestacoes_historico"
    exit 0
fi

git push origin 1_gestacoes_historico

if [ $? -eq 0 ]; then
    print_success "Push realizado com sucesso!"
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}✅ Publicação concluída com sucesso!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo "📂 Arquivos publicados em:"
    echo "   https://github.com/nucleoia-sap/sql-monitor-gestante-historico/tree/1_gestacoes_historico/SQL_histórico"
    echo ""
    echo "🔄 Próximos passos (opcional):"
    echo "   1. Criar Pull Request para mesclar com main"
    echo "   2. Acessar: https://github.com/nucleoia-sap/sql-monitor-gestante-historico"
    echo "   3. Clicar em 'Compare & pull request'"
    echo ""
else
    print_error "Falha no push!"
    echo "Possíveis causas:"
    echo "  - Sem permissão no repositório"
    echo "  - Branch remoto desatualizado (use: git pull origin 1_gestacoes_historico)"
    echo "  - Sem conexão com internet"
    exit 1
fi

# ============================================================
# Fim
# ============================================================

print_success "Script concluído!"
