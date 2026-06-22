# oAsIs — OS appliance IA

Transforme un PC dédié (testé sur **Acer Aspire Vero**, Intel + Iris Xe, sans GPU) en
**ordinateur dédié à l'IA** : un **chatbot local** qui s'ouvre au démarrage, plus, au choix,
**FreeCAD** (modélisation 3D) et **Krita** (dessin, tablette **Veikk**).

Pas un OS écrit de zéro (Yocto serait des semaines de galère pour FreeCAD/Krita/Ollama) :
une base **Ubuntu 24.04 LTS** + un **script de provisioning idempotent**. Le script *est* la
définition de l'OS — rejouable, versionné, « flashable » comme un firmware.

## Pile logicielle

| Brique | Rôle |
|---|---|
| **Ollama** | moteur LLM local (service systemd) |
| **Open WebUI** | interface de chat (Docker, port 8080, redémarre seule) |
| **FreeCAD / Krita** | optionnels (apt) |
| **pilote Veikk (DKMS)** | pression du stylet, optionnel |
| Chromium `--app` (autostart) | le chatbot s'ouvre au login, bureau gardé utilisable |

Le **chat IA est toujours installé** ; FreeCAD / Krita / Veikk sont au choix
(questions en mode manuel, ou variables `INSTALL_FREECAD` / `INSTALL_KRITA` / `INSTALL_VEIKK=0|1`).

## Fichiers

- **`setup-appliance.sh`** — provisioning. À lancer sur un Ubuntu fraîchement installé :
  `bash setup-appliance.sh` (16 Go RAM : `MODEL=mistral:7b bash setup-appliance.sh`).
- **`user-data`** / **`meta-data`** — config **autoinstall** Ubuntu (cloud-init NoCloud).
  Installe Ubuntu sans interaction et lance le script au 1er démarrage. Le script y est
  embarqué en base64. ⚠️ **Remplace les placeholders Wi‑Fi** (`YOUR_WIFI_SSID` /
  `YOUR_WIFI_PASSWORD`) et **change le mot de passe** `ia` (hash via `openssl passwd -6`).
- **`prepare-key.ps1`** — utilitaire Windows : efface une clé USB et la formate FAT32
  label `CIDATA` (garde-fou : refuse tout sauf une clé USB). À lancer en admin.
- **`iso.sha256`** — version d'ISO Ubuntu épinglée + empreinte.

## Usage : clé unique auto-installante

1. **Rufus** écrit l'ISO Ubuntu 24.04 Desktop sur la clé, en **« mode Image ISO »**.
2. Copier le dossier de config NoCloud sur la clé et activer `autoinstall`
   (seed `user-data`/`meta-data` + paramètre noyau, ou 2ᵉ partition labellisée `CIDATA`).
3. Démarrer la machine cible sur la clé → install Ubuntu non interactive, puis provisioning
   automatique au 1er boot.

> Le 1er démarrage **nécessite Internet** (télécharge Ollama, le modèle, le chatbot, les applis).
> En Wi‑Fi, les identifiants doivent être renseignés dans `user-data` **avant**.

## Matériel & modèles

CPU only (Iris Xe) → petits modèles : `llama3.2:3b` (~4–6 mots/s) par défaut ;
`mistral:7b` si ≥ 16 Go RAM (meilleur en français, plus lent).
