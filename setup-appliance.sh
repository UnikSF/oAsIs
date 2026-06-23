#!/usr/bin/env bash
# setup-appliance.sh — transforme un Ubuntu 24.04 fraichement installe en
# "OS appliance IA".
#   - Le chat IA (Ollama + Open WebUI) est TOUJOURS installe, EN PRIORITE.
#   - FreeCAD / Krita / pilote Veikk sont AU CHOIX et n'empechent PAS le
#     chat IA de s'installer s'ils echouent.
# Idempotent : re-executable sans rien casser.
#
# Choix : questions (terminal) ou variables INSTALL_FREECAD/INSTALL_KRITA/INSTALL_VEIKK=0|1
#   16 Go RAM ? MODEL=mistral:7b bash setup-appliance.sh
set -euo pipefail

MODEL="${MODEL:-llama3.2:3b}"

# want VAR "Question ?" -> 0 si on installe. env (1/0) > question (terminal) > defaut OUI.
want() {
  local var="$1" q="$2" ans v="${!1:-}"
  if [ -n "$v" ]; then [ "$v" = "1" ]; return; fi
  if [ -t 0 ]; then read -rp "$q (O/n) " ans; [[ "${ans:-O}" =~ ^[OoYy] ]]; return; fi
  return 0
}

echo "== Configuration de l'appliance IA (le chat IA est toujours installe) =="
FREECAD=0; KRITA=0; VEIKK=0
want INSTALL_FREECAD "Installer FreeCAD (modeleur 3D) ?" && FREECAD=1 || true
want INSTALL_KRITA   "Installer Krita (dessin) ?"        && KRITA=1   || true
want INSTALL_VEIKK   "Installer le pilote tablette Veikk ?" && VEIKK=1 || true

echo "==> Attente d'une connexion Internet (le Wi-Fi met qq sec a s'associer; max 5 min)..."
for _ in $(seq 1 60); do
  curl -fsS --max-time 5 https://archive.ubuntu.com >/dev/null 2>&1 && { echo "   reseau OK"; break; }
  sleep 5
done

echo "==> 1/4  Paquets de base"
sudo add-apt-repository -y universe >/dev/null 2>&1 || true   # FreeCAD/Krita y sont
sudo apt-get update
sudo apt-get install -y curl git docker.io chromium-browser

echo "==> 2/4  Le chat IA (Ollama + Open WebUI) -- priorite"
command -v ollama >/dev/null || curl -fsSL https://ollama.com/install.sh | sh
ollama pull "$MODEL"
sudo systemctl enable --now docker
if ! sudo docker ps -a --format '{{.Names}}' | grep -qx open-webui; then
  sudo docker run -d --network=host -v open-webui:/app/backend/data \
    -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
    --restart always --name open-webui ghcr.io/open-webui/open-webui:main
fi

echo "==> 3/4  Applis optionnelles (n'interrompent PAS le chat IA)"
# Krita + deps Veikk via apt ; FreeCAD via snap (absent des depots Ubuntu 24.04)
OPT=()
[ "$KRITA" = 1 ] && OPT+=(krita)
[ "$VEIKK" = 1 ] && OPT+=(dkms build-essential "linux-headers-$(uname -r)")
if [ "${#OPT[@]}" -gt 0 ]; then
  for p in "${OPT[@]}"; do
    sudo apt-get install -y "$p" || echo "   (echec '$p' -- on continue)"
  done
fi
if [ "$FREECAD" = 1 ]; then
  echo "   FreeCAD (via snap -- absent des depots Ubuntu 24.04)"
  sudo snap install freecad || echo "   (FreeCAD non installe -- on continue)"
fi
if [ "$VEIKK" = 1 ] && ! dkms status 2>/dev/null | grep -qi veikk; then
  echo "   Pilote tablette Veikk (DKMS)"
  { git clone https://github.com/jlam55555/veikk-linux-driver "$HOME/veikk-linux-driver" \
      || ( cd "$HOME/veikk-linux-driver" && git pull ); } || true
  ( cd "$HOME/veikk-linux-driver" && sudo make dkms ) || echo "   (pilote Veikk non compile -- on continue)"
fi

echo "==> 4/4  Demarrage auto du chatbot (fenetre, bureau garde utilisable)"
sudo tee /usr/local/bin/launch-chatbot.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
B="$(command -v chromium-browser || command -v chromium)"
# Open WebUI telecharge ~900 Mo (modele embedding) a son 1er demarrage avant de
# repondre sur :8080 -> on attend jusqu'a ~20 min (surtout en partage 4G).
for _ in $(seq 1 600); do curl -sf http://localhost:8080 >/dev/null && break; sleep 2; done
exec "$B" --app=http://localhost:8080
EOF
sudo chmod +x /usr/local/bin/launch-chatbot.sh
USR="$(id -un 1000 2>/dev/null || echo "$USER")"
HOMEDIR="$(getent passwd "$USR" | cut -d: -f6)"
sudo -u "$USR" mkdir -p "$HOMEDIR/.config/autostart"
sudo tee "$HOMEDIR/.config/autostart/chatbot.desktop" >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Chatbot IA
Exec=/usr/local/bin/launch-chatbot.sh
X-GNOME-Autostart-enabled=true
EOF
sudo chown -R "$USR:$USR" "$HOMEDIR/.config/autostart"

echo
echo "OK. Le chat IA est installe. Redemarre -- le chatbot s'ouvrira tout seul."
echo "1er lancement du chatbot : cree le compte admin (le 1er compte = admin)."
