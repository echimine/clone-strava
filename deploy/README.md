# deploy/ — fichiers prêts à copier sur le VPS (ADR-018)

Ce dossier est commité pour traçabilité et revue, mais **rien ici n'est exécuté depuis ce
repo ni par le CI**. Ce sont des modèles à déposer manuellement sur le VPS OVH GRA-01, dans
`/opt/www/strava.echimine.fr/prod/`, en suivant le pattern GHCR → webhook → VPS (skill
`deploy-vps`, ADR-018).

| Fichier | Destination VPS | Commentaire |
|---|---|---|
| `docker-compose.yml` | `/opt/www/strava.echimine.fr/prod/docker-compose.yml` | À copier tel quel |
| `redis.conf` | `/opt/www/strava.echimine.fr/prod/redis.conf` | Remplacer `<REDIS_PASSWORD>` par la vraie valeur (Apple Mots de passe), identique à `REDIS_PASSWORD` dans `.env` |
| `env.prod.template` | `/opt/www/strava.echimine.fr/prod/.env` | Renommer en `.env`, remplir les valeurs (Apple Mots de passe), puis `chmod 600` |
| `hooks.json` | à fusionner dans `/opt/proxy/webhook/hooks.json` (webhook mutualisé) | **Ne pas écraser** : ajouter l'objet `deploy-strava` au tableau JSON existant, à côté de `deploy-sori`. Réutilise la même variable partagée `{{ getenv \`DEPLOY_TOKEN\` }}` que les autres apps (un seul token pour tout le conteneur webhook) : le secret GitHub `DEPLOY_WEBHOOK_SECRET` de ce repo doit valoir exactement cette même valeur. |
| `deploy.sh` | `/opt/proxy/webhook/deploy-strava.sh` (monté dans le conteneur webhook en `/scripts/deploy-strava.sh`, **pas** dans le dossier applicatif) | `chmod +x`, owner cohérent avec les autres scripts du dossier (`eliott:deploy` sur ce VPS). Le hook fixe `command-working-directory` sur `/opt/www/strava.echimine.fr/prod` : le script hérite ce `cwd`, il ne le recalcule pas depuis `$0`. |
| `backup-strava-db.service` / `.timer` | `/etc/systemd/system/` | `daemon-reload` puis `enable --now` le timer |

Le `docker-compose.yml` du webhook mutualisé (`/opt/proxy/webhook/docker-compose.yml`, hors de ce
repo) doit monter en plus : `./deploy-strava.sh:/scripts/deploy-strava.sh:ro` et
`/opt/www/strava.echimine.fr/prod:/opt/www/strava.echimine.fr/prod:ro`. Un ajout de volume
demande de recréer le conteneur (`docker compose up -d`) ; `hooks.json` seul est rechargé à chaud
(`-hotreload`).

Un fichier `.discord-webhook-url` (URL du webhook Discord de notification, `chmod 600`) est
aussi requis dans `/opt/www/strava.echimine.fr/prod/`, hors de ce repo (non listé ci-dessus).

Aucune valeur secrète n'est présente dans ce dossier : uniquement des placeholders et des
noms de clés. Voir la checklist VPS complète fournie par l'agent `deploy-vps` (rapport de
génération) pour l'ordre exact des opérations.
