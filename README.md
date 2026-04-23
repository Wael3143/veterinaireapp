# VétérinApp Pro v5 — Dr. Kherbache Wail

Application vétérinaire web · ENSV Algérie 🇩🇿

## Déploiement
- Hébergé sur **Vercel** (auto-deploy depuis GitHub)
- Auth sécurisée via **Supabase**

## Mise à jour
1. Modifier `index.html` localement
2. `git add . && git commit -m "update" && git push`
3. Vercel redéploie automatiquement en ~30 secondes

## Configuration Supabase
Remplacer dans `index.html` :
- `VOTRE_SUPABASE_URL` → URL de votre projet Supabase
- `VOTRE_SUPABASE_ANON_KEY` → Clé anon publique Supabase
