# VetPro

Application vétérinaire web pour VetPro Algérie — clinique mono-fichier (vanilla JS) déployée sur Vercel, base Supabase, IA via Edge Function vers OpenRouter (Llama 3.3 70B Instruct, gratuit).

## Fichiers principaux

- `index.html` — application complète (SPA)
- `vetpro-logo.jpg`, `vetpro-logo-mark.svg` — logos
- `supabase/migrations/20260425_vetpro_full_schema.sql` — **migration consolidée** (profiles, approbations, essai, RLS, indexes, RPC `reset_user_data`, RPC `approve_user`, triggers)
- `supabase/functions/vetpro-ai/index.ts` — Edge Function qui appelle OpenRouter côté serveur (la clé API n'est jamais exposée au navigateur)
- `supabase-setup.sql`, `supabase-fix.sql` — anciens scripts (conservés pour historique, **ne plus exécuter** : remplacés par la migration ci-dessus)
- `vercel.json` — config Vercel (static + headers sécurité)

## Démarrage rapide (3 étapes)

1. Lancer la migration Supabase (voir « Exécuter la migration » plus bas).
2. Définir les secrets Edge Function (clé OpenRouter).
3. Déployer sur Vercel : push sur `main`, Vercel redéploie automatiquement.

## Variables d'environnement

### Supabase Edge Function `vetpro-ai`
À définir dans **Supabase Dashboard → Project Settings → Edge Functions → Secrets** (ou via `supabase secrets set` en CLI). **Aucune de ces valeurs ne doit apparaître dans `index.html` ni dans le navigateur.**

| Nom | Valeur recommandée |
|---|---|
| `OPENROUTER_API_KEY` | votre clé `sk-or-v1-…` (privée) |
| `OPENROUTER_MODEL` | `meta-llama/llama-3.3-70b-instruct:free` |
| `OPENROUTER_BASE_URL` | `https://openrouter.ai/api/v1` *(optionnel — la fonction utilise `/chat/completions` par défaut)* |
| `OPENROUTER_APP_NAME` | `VetPro` |
| `OPENROUTER_SITE_URL` | URL de votre site Vercel (ex. `https://vetpro.vercel.app`) |
| `SUPABASE_URL` | injecté automatiquement |
| `SUPABASE_ANON_KEY` | injecté automatiquement |

### Vercel
Aucune variable n'est strictement requise pour le frontend (la clé Supabase anon est publique par design — RLS protège les données). Si vous gardez une page d'admin email statique, vous pouvez ajouter :
- `NEXT_PUBLIC_ADMIN_EMAIL=waillacamora31@gmail.com` *(non utilisé par l'app actuelle, conservé pour évolution future)*

> ⚠️ **La clé `service_role` Supabase ne doit JAMAIS apparaître dans Vercel ni dans le HTML.** Elle reste uniquement côté Supabase.

## Exécuter la migration

### Option A — SQL Editor (le plus simple)
1. Ouvrir Supabase → SQL Editor.
2. Copier le contenu de `supabase/migrations/20260425_vetpro_full_schema.sql`.
3. Coller et exécuter. Le script est **idempotent** : on peut le relancer sans risque.

### Option B — Supabase CLI
```bash
supabase link --project-ref smzmuqgbtsjgetxbmdgq
supabase db push
```

### Ce que la migration installe
- Table `profiles` (rôle `user`/`admin`) + auto-création à la signup via trigger `on_auth_user_created`.
- Extension de `vetpro_access_requests` avec `trial_started_at`, `trial_ends_at`, `access_expires_at`, `approved_by`, `approved_at`, `created_at`, `updated_at`.
- Nouvelle table `vetpro_user_settings` (langue, thème, infos clinique, préférences notifications).
- RLS stricte sur **toutes** les tables, basée sur `auth.uid()` + helper `is_admin()`.
- Index sur `email` (lower), `user_id`, `status`, `access_expires_at`.
- RPC `reset_user_data(include_settings boolean)` — un utilisateur reset uniquement ses propres données.
- RPC `approve_user(target_email, mode, duration_days, until_date)` — admin uniquement, modes : `permanent`, `until`, `days`, `trial` (15 j), `reject`.
- Vue `my_access_status` — statut effectif (avec calcul d'expiration).
- L'email admin `waillacamora31@gmail.com` est créé en `profile.role='admin'` automatiquement (au signup ou en backfill si déjà existant).

## Devenir / vérifier l'admin

L'admin n'est plus identifié par `localStorage`. Il est lu depuis la table `profiles` (RLS). Pour qu'un email soit admin :

1. Cet email doit avoir un compte créé dans Supabase Auth (`Authentication → Users`).
2. Le trigger `handle_new_user` lui assigne `role='admin'` automatiquement si l'email est `waillacamora31@gmail.com`.
3. Pour un autre admin, exécuter dans le SQL Editor :
   ```sql
   update public.profiles set role='admin' where lower(email)=lower('autre@admin.dz');
   ```

L'onglet **Approbations** apparaît automatiquement dans la sidebar pour les administrateurs (et est masqué pour les autres).

## Déployer la Edge Function (IA)

```bash
supabase functions deploy vetpro-ai --project-ref smzmuqgbtsjgetxbmdgq
supabase secrets set OPENROUTER_API_KEY=sk-or-v1-...
supabase secrets set OPENROUTER_MODEL=meta-llama/llama-3.3-70b-instruct:free
```

Le frontend appelle `_sb.functions.invoke('vetpro-ai', { body: {...} })` — **jamais** `openrouter.ai` directement.

## Système d'approbation & essai

Workflow :
1. L'utilisateur s'inscrit → row `pending` créée dans `vetpro_access_requests`.
2. À la connexion, le frontend appelle la vue `my_access_status` :
   - `pending` → écran « En attente d'approbation »
   - `rejected` → écran « Accès refusé »
   - `expired` → écran « Accès expiré » (essai ou date limite dépassés)
   - `approved` / `trial` valides → accès complet
   - `admin` → accès complet + onglet Approbations
3. Dans l'onglet Approbations, l'admin peut :
   - **Approuver** (permanent)
   - **Essai 15 j** (champ `trial_ends_at`)
   - **Approuver N jours** (saisir nombre + clic)
   - **Jusqu'à date** (saisir date + clic)
   - **Refuser** (statut `rejected`)
4. L'expiration est calculée par la vue `my_access_status` côté serveur (pas de contournement frontend possible).

## Persistance des données

Toutes les données cliniques (cas, clients, animaux, finances, cages, hospitalisations, rappels, vaccinations, RDV, stock, historique) sont stockées **par utilisateur** dans `vetpro_user_state.state` (JSON), filtré par RLS sur `user_id`/`email`. Le localStorage reste un cache rapide ; l'autorité c'est Supabase.

Les paramètres (langue, thème, infos clinique, notifications) sont dans `vetpro_user_settings`.

### « Réinitialiser à 0 »
Bouton dans **Paramètres → Sécurité & Données**. Demande confirmation, appelle `reset_user_data()` (RPC), efface les données cliniques de l'utilisateur courant **uniquement**, garde langue/thème.

## i18n (FR / AR / EN)

- Sélecteur dans **Paramètres → Affichage → Langue interface**.
- Persiste dans `vetpro_user_settings.language` + `localStorage` (cache).
- L'arabe active automatiquement `dir="rtl"` et la classe `vp-rtl` sur `<body>`.
- Tableaux de bord, sidebar, libellés principaux et écrans d'accès traduits. Les écrans détaillés (cas, ordonnances, etc.) restent en français — base i18n posée pour traduction incrémentale via `window.vpT('clé')`.

## Bug de message de bienvenue (corrigé)

Avant : « Bonjour Dr. … 👋 » s'affichait à chaque retour sur le tableau de bord.

Désormais : drapeau `sessionStorage['vetpro-welcomed-once']` — message affiché à la première arrivée au dashboard après connexion, puis remplacé par un titre neutre traduit. Le drapeau est effacé à la déconnexion ou à un nouveau `SIGNED_IN`.

## Mobile

Hamburger flottant en haut à gauche (en haut à droite en RTL), sidebar coulissante, grilles 1-colonne sous 768 px, tables défilables horizontalement, modales adaptées à la hauteur d'écran, boutons à 44 px min pour le tactile. Testé visuellement sur 360 / 390 / 414 / 768 px.

## Checklist de test

- [ ] Connexion admin (`waillacamora31@gmail.com`) → onglet « Approbations » visible.
- [ ] Inscription nouvel utilisateur → écran « En attente d'approbation ».
- [ ] Admin clique « Essai 15j » → l'utilisateur peut accéder.
- [ ] Admin clique « Approuver N jours » avec 1 → après 1 jour, l'utilisateur est bloqué (« Accès expiré »).
- [ ] User A crée un client → User B ne le voit pas (RLS).
- [ ] User A refresh → données conservées.
- [ ] User A → Paramètres → « Réinitialiser à 0 » → seules ses données sont effacées.
- [ ] Sélecteur Langue → AR : interface en arabe, RTL appliqué.
- [ ] Tableau de bord : message de bienvenue n'apparaît qu'une fois par session.
- [ ] IA : `_sb.functions.invoke('vetpro-ai', …)` retourne une réponse Llama.
- [ ] Mobile (360 px) : sidebar masquée, hamburger fonctionnel, pas de scroll horizontal sur la home.

## Risques connus / TODOs restants

- **Traduction incrémentale** : seuls le tableau de bord, la sidebar, les paramètres et les écrans d'accès sont entièrement traduits. Les pages métier (cas, ordonnances, finances…) restent en français — utiliser `window.vpT('clé')` pour les traduire au fil du temps.
- **Sauvegarde paramètres → champs hardcodés** : le bouton « Sauvegarder » des paramètres mappe les champs par index. Si l'ordre des inputs change, mettre à jour `vpSaveSettings` dans `index.html`.
- **Migration de l'existant** : si vous avez déjà des rows dans `vetpro_user_state` sans `user_id`, la migration les laisse en place. Pour les forcer à s'attacher à un user_id, exécuter manuellement :
  ```sql
  update public.vetpro_user_state s set user_id = u.id
    from auth.users u where lower(u.email) = lower(s.email) and s.user_id is null;
  ```
- **Clé anon Supabase exposée** : c'est normal pour une app browser. La sécurité repose sur la RLS (vérifiée par la migration). En cas de doute, faire une rotation de la clé dans Supabase puis remplacer la valeur dans `index.html` ligne 843.

## Mise en ligne

1. `git add . && git commit -m "..."`
2. `git push origin main`
3. Vercel déploie automatiquement (config dans `vercel.json`).
