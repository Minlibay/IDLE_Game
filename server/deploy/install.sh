#!/usr/bin/env bash
# Установка сервера мировой карты на чистую Ubuntu 24.04 (запускать от root или через sudo).
#   sudo bash install.sh world.example.com     # с доменом: nginx + бесплатный HTTPS (Let's Encrypt)
#   sudo bash install.sh                       # без домена: сервер на http://<IP>:8787
set -euo pipefail

DOMAIN="${1:-}"
REPO="https://github.com/Minlibay/IDLE_Game.git"
APP_DIR=/opt/idle-heroes
DATA_DIR=/var/lib/idle-heroes
SERVICE=idle-heroes-world

echo "== Node.js 24 (NodeSource) =="
if ! command -v node >/dev/null || [[ "$(node -p 'process.versions.node.split(".")[0]')" -lt 24 ]]; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg git
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y nodejs
fi
node --version

echo "== Пользователь и папки =="
id idleheroes >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin idleheroes
mkdir -p "$DATA_DIR"
chown idleheroes:idleheroes "$DATA_DIR"

echo "== Код =="
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" pull --ff-only
else
  git clone --depth 1 "$REPO" "$APP_DIR"
fi
chown -R idleheroes:idleheroes "$APP_DIR"

echo "== Проверка: тесты сервера =="
(cd "$APP_DIR/server" && sudo -u idleheroes npm test)

echo "== Служба systemd =="
cp "$APP_DIR/server/deploy/$SERVICE.service" /etc/systemd/system/
if [[ -z "$DOMAIN" ]]; then
  # Без домена слушаем на всех интерфейсах.
  sed -i 's/^Environment=HOST=127.0.0.1/Environment=HOST=0.0.0.0/' "/etc/systemd/system/$SERVICE.service"
fi
systemctl daemon-reload
systemctl enable --now "$SERVICE"

echo "== Брандмауэр =="
apt-get install -y ufw
ufw allow OpenSSH
if [[ -n "$DOMAIN" ]]; then
  ufw allow 'Nginx Full' || true
else
  ufw allow 8787/tcp
fi
ufw --force enable

if [[ -n "$DOMAIN" ]]; then
  echo "== nginx + HTTPS для $DOMAIN =="
  apt-get install -y nginx certbot python3-certbot-nginx
  sed "s/world.example.com/$DOMAIN/g" "$APP_DIR/server/deploy/nginx-idle-heroes.conf" > /etc/nginx/sites-available/idle-heroes
  ln -sf /etc/nginx/sites-available/idle-heroes /etc/nginx/sites-enabled/idle-heroes
  nginx -t && systemctl reload nginx
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect
  echo "Готово: в игре на экране входа укажите https://$DOMAIN"
else
  IP="$(curl -fsS https://api.ipify.org || hostname -I | awk '{print $1}')"
  echo "Готово: в игре на экране входа укажите http://$IP:8787 (без шифрования — для теста)"
fi

systemctl --no-pager status "$SERVICE" | head -n 5
