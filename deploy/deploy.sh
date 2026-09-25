#!/usr/bin/env bash
# À déposer sur le VPS en /opt/www/strava.echimine.fr/prod/deploy.sh (chmod +x, owner deploy),
# OU monté séparément (ex: /scripts/deploy-strava.sh dans le conteneur webhook mutualisé) tant
# que le hook fixe `command-working-directory` sur le dossier applicatif (cwd hérité, PAS calculé
# depuis $0 : ce script peut vivre ailleurs que le dossier qu'il déploie).
# Repris tel quel du template skill deploy-vps (pull && up -d --wait && vérif healthy stricte
# + notification Discord), avec EXPECTED_SERVICES adapté aux 6 services de la stack strava.
# Requiert bash, docker compose, jq, curl, timeout, flock.
set -Eeuo pipefail
[[ -n "${APP_DIR:-}" ]] && cd "$APP_DIR"
APP_NAME=${APP_NAME:-$(basename "$(dirname "$PWD")")}
DEPLOY_TIMEOUT=${DEPLOY_TIMEOUT:-300}
EXPECTED_SERVICES=${EXPECTED_SERVICES:-"db redis api worker realtime admin"}
DISCORD_WEBHOOK_FILE=${DISCORD_WEBHOOK_FILE:-.discord-webhook-url}
phase=configuration
notify() {
  local url payload
  url=$(cat "$DISCORD_WEBHOOK_FILE") || return 1
  [[ "$url" == https://discord.com/api/webhooks/* && "$url" != *$'\n'* && "$url" != *'"'* && "$url" != *'\'* && "$url" != *$'\r'* ]] || return 1
  payload=$(jq -nc --arg content "$1" '{content: $content, allowed_mentions: {parse: []}}') || return 1
  # URL via stdin pour ne pas exposer le secret dans la liste des processus.
  printf 'url = "%s?wait=true"\n' "${url%%\?*}" |
    curl --config - --silent --fail --connect-timeout 5 --max-time 15 \
      -H 'Content-Type: application/json' --data "$payload" --output /dev/null
}
finish() {
  local rc=$?
  trap - EXIT
  if (( rc != 0 )); then
    printf '[deploy] ÉCHEC : %s (code %s)\n' "$phase" "$rc" >&2
    notify "❌ $APP_NAME : déploiement échoué à l'étape $phase (code $rc). Consulter les logs du webhook." ||
      echo '[deploy] Notification Discord non remise.' >&2
  fi
  exit "$rc"
}
for dependency in docker jq curl timeout flock; do
  command -v "$dependency" >/dev/null || { echo "Dépendance absente : $dependency" >&2; exit 1; }
done
[[ "$DEPLOY_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || exit 1
[[ -s "$DISCORD_WEBHOOK_FILE" ]] || { echo 'Fichier webhook Discord absent/vide.' >&2; exit 1; }
# Même verrou pour tous les appels utilisant ce répertoire ; aucun deploy concurrent.
lock_key=$(printf %s "$PWD" | cksum | cut -d' ' -f1)
exec 9>"/tmp/deploy-$lock_key.lock"
flock -n 9 || { echo '[deploy] Déploiement déjà en cours.' >&2; exit 1; }
trap finish EXIT
read -r -a services <<< "$EXPECTED_SERVICES"
(( ${#services[@]} > 0 ))
# Les healthchecks peuvent être hérités des images : validation après démarrage.
phase=pull
timeout "$DEPLOY_TIMEOUT" docker compose pull "${services[@]}"
phase='démarrage / attente healthy (timeout ou unhealthy)'
timeout "$DEPLOY_TIMEOUT" docker compose up -d --wait --wait-timeout "$DEPLOY_TIMEOUT" "${services[@]}"
# Compose accepte running sans healthcheck : inspection stricte, y compris les répliques.
phase='vérification finale des conteneurs attendus'
for service in "${services[@]}"; do
  ids=$(timeout 15 docker compose ps --all -q "$service")
  [[ -n "$ids" ]] || exit 1
  while IFS= read -r id; do
    state=$(timeout 15 docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$id")
    [[ "$state" == 'running healthy' ]] || exit 1
  done <<< "$ids"
done
phase='notification Discord (conteneurs healthy)'
# Un échec de remise reste un code non nul, sans annoncer à tort un échec applicatif.
trap - EXIT
notify "✅ $APP_NAME : déploiement terminé, services $EXPECTED_SERVICES healthy." || {
  echo '[deploy] Conteneurs healthy, mais notification Discord non remise.' >&2
  exit 1
}
echo '[deploy] done : tous les conteneurs attendus sont healthy.'
