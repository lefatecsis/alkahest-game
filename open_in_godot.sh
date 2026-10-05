#!/bin/bash
# Script para encontrar e abrir o projeto no Godot 4

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Tenta encontrar o Godot instalado
GODOT_CANDIDATES=(
    "godot4"
    "godot"
    "Godot_v4"
    "$HOME/Godot_v4.3-stable_linux.x86_64"
    "$HOME/godot"
    "$HOME/.local/bin/godot4"
    "$HOME/.local/bin/godot"
    "/usr/bin/godot4"
    "/usr/bin/godot"
    "/usr/local/bin/godot4"
    "/usr/local/bin/godot"
    "/opt/godot/godot"
)

# Verifica AppImages na home
for f in "$HOME"/*.AppImage "$HOME"/Godot*.AppImage "$HOME"/Downloads/Godot*.AppImage; do
    [ -f "$f" ] && GODOT_CANDIDATES+=("$f")
done

# Verifica Flatpak
if flatpak list 2>/dev/null | grep -qi godot; then
    GODOT_CANDIDATES+=("flatpak run org.godotengine.Godot")
fi

GODOT_BIN=""
for candidate in "${GODOT_CANDIDATES[@]}"; do
    # Testa se é um comando válido
    if command -v "$candidate" &>/dev/null || [ -x "$candidate" ]; then
        GODOT_BIN="$candidate"
        break
    fi
done

if [ -z "$GODOT_BIN" ]; then
    echo "❌ Godot não encontrado!"
    echo ""
    echo "Instale o Godot 4 e tente novamente:"
    echo "  • Baixe em: https://godotengine.org/download/linux/"
    echo "  • Ou via Flatpak: flatpak install flathub org.godotengine.Godot"
    echo ""
    echo "Depois execute: godot4 --path '$PROJECT_DIR'"
    exit 1
fi

echo "✅ Abrindo projeto com: $GODOT_BIN"
echo "   Diretório: $PROJECT_DIR"
"$GODOT_BIN" --path "$PROJECT_DIR" &
