#!/usr/bin/env bash
# setup-appliance.sh — transforme un Ubuntu 24.04 fraichement installe en
# "OS appliance IA".
#   - Le chat IA (Ollama + Open WebUI) est TOUJOURS installe.
#   - Les applis metier (FreeCAD, Krita, tablette Veikk) sont AU CHOIX.
# Idempotent : re-executable sans rien casser.
#
# Choix des applis :
#   - en manuel (terminal) : le script POSE la question pour chaque appli.
#   - en auto (cloud-init, sans terminal) : via variables, sinon tout par defaut.
#       INSTALL_FREECAD / INSTALL_KRITA / INSTALL_VEIKK = 1 (oui) ou 0 (non)
#
# Usage :   bash setup-appliance.sh
#   16 Go RAM ? meilleur modele francais (plus lent) :
#           MODEL=mistral:7b bash setup-appliance.sh
#   tout sauf Krita/Veikk, sans questions :
#           INSTALL_KRITA=0 INSTALL_VEIKK=0 bash setup-appliance.sh
set -euo pipefail

# 8 Go RAM -> 3B (rapide). 16 Go -> mistral:7b possible.
MODEL="${MODEL:-llama3.2:3b}"

# want VAR "Question ?"  -> code 0 si on installe.
# Priorite : variable d'env (1/0) > question (si terminal) > defaut OUI.
want() {
  local var="$1" q="$2" ans v="${!1:-}"
  if [ -n "$v" ]; then [ "$v" = "1" ]; return; fi
  if [ -t 0 ]; then read -rp "$q (O/n) " ans; [[ "${ans:-O}" =~ ^[OoYy] ]]; return; fi
  return 0
}

echo "== Configuration de l'appliance IA (le chat IA est toujours installe) =="
APPS=(curl git docker.io chromium-browser)   # base + chat : toujours
want INSTALL_FREECAD "Installer FreeCAD (modeleur 3D) ?" && APPS+=(freecad) || true
want INSTALL_KRITA   "Installer Krita (dessin) ?"        && APPS+=(krita)   || true
VEIKK=0
if want INSTALL_VEIKK "Installer le pilote tablette Veikk ?"; then
  VEIKK=1; APPS+=(dkms build-essential "linux-headers-$(uname -r)")
fi

echo "==> Attente d'une connexion Internet (le Wi-Fi met qq sec a s'associer; max 5 min)..."
for _ in $(seq 1 60); do
  curl -fsS --max-time 5 https://archive.ubuntu.com >/dev/null 2>&1 && { echo "   reseau OK"; break; }
  sleep 5
done

echo "==> 1/4  Paquets : ${APPS[*]}"
sudo apt-get update
sudo apt-get install -y "${APPS[@]}"

echo "==> 2/4  Ollama (moteur LLM, service systemd auto)"
command -v ollama >/dev/null || curl -fsSL https://ollama.com/install.sh | sh
ollama pull "$MODEL"

echo "==> 3/4  Open WebUI (chatbot, Docker, redemarre tout seul)"
sudo systemctl enable --now docker
if ! sudo docker ps -a --format '{{.Names}}' | grep -qx open-webui; then
  sudo docker run -d --network=host -v open-webui:/app/backend/data \
    -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
    --restart always --name open-webui ghcr.io/open-webui/open-webui:main
fi

if [ "$VEIKK" = 1 ] && ! dkms status 2>/dev/null | grep -qi veikk; then
  echo "==> Pilote tablette Veikk (pression du stylet, via DKMS)"
  git clone https://github.com/jlam55555/veikk-linux-driver "$HOME/veikk-linux-driver" \
    || (cd "$HOME/veikk-linux-driver" && git pull)
  ( cd "$HOME/veikk-linux-driver" && sudo make dkms )
fi

echo "==> 4/4  Demarrage auto du chatbot (fenetre, bureau garde utilisable)"
sudo tee /usr/local/bin/launch-chatbot.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# attend que le chatbot reponde (1er boot : Docker met du temps), puis l'ouvre
B="$(command -v chromium-browser || command -v chromium)"
for _ in $(seq 1 60); do curl -sf http://localhost:8080 >/dev/null && break; sleep 2; done
exec "$B" --app=http://localhost:8080
EOF
sudo chmod +x /usr/local/bin/launch-chatbot.sh

# Cible le compte du bureau (UID 1000) -> marche en manuel ET en auto (cloud-init/root)
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
echo "OK. Redemarre le Vero."
echo "1er lancement du chatbot : cree le compte admin (le 1er compte = admin)."
