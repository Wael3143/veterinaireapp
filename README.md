# VetPro

Application veterinaire web pour VetPro Algerie.

## Fichiers importants

- `index.html` : application complete
- `vetpro-logo.jpg` : logo utilise sur la landing et la connexion
- `supabase-setup.sql` : tables et policies Supabase pour l'approbation et les messages contact

## Mise en ligne

1. Modifier `index.html`
2. Pousser vers GitHub
3. Vercel redeploie automatiquement

## Configuration Supabase pas a pas

1. Ouvrir votre projet Supabase
2. Aller dans `SQL Editor`
3. Ouvrir le fichier [`supabase-setup.sql`](C:\Users\david\Documents\GitHub\veterinaireapp\supabase-setup.sql)
4. Remplacer `__ADMIN_EMAIL__` par votre vrai email admin prive
5. Copier tout le contenu et lancer le script dans Supabase
6. Aller dans `Authentication` > `Providers` > `Email`
7. Si vous voulez des connexions immediates, desactiver la confirmation email obligatoire
8. Aller dans `Authentication` > `Providers` > `Google`
9. Activer Google et copier le `Callback URL` donne par Supabase dans votre console Google Cloud OAuth
10. Dans le navigateur local, definir:
11. `localStorage.setItem('vetpro-admin-email','votre-email-admin')`
12. `localStorage.setItem('vetpro-contact-email','votre-email-contact')`
13. Verifier que votre email admin existe dans `Authentication` > `Users`
14. Se connecter avec ce compte admin
15. Aller dans l'onglet `Approbations` pour approuver les autres utilisateurs

## Comment devenir admin exactement

1. Choisir l'email qui sera admin
2. Mettre cet email a la place de `__ADMIN_EMAIL__` dans `supabase-setup.sql`
3. Executer le SQL dans Supabase
4. Creer ou verifier ce meme compte dans `Authentication > Users`
5. Dans votre navigateur, executer `localStorage.setItem('vetpro-admin-email','le-meme-email')`
6. Connectez-vous avec ce compte
7. Votre compte sera reconnu comme admin

## Ce que fait Supabase

- Table `vetpro_access_requests` : stocke les demandes d'acces
- Table `vetpro_contact_messages` : stocke les messages envoyes depuis la page contacts
- Table `vetpro_user_state` : stocke tous les cas, clients, rendez-vous, rappels et autres donnees de l'application en JSON par utilisateur
- Policies RLS : seuls les admins peuvent approuver et lire tous les messages

## Note importante

Le depot public ne contient plus d'email personnel ni de mot de passe admin. Configurez les emails admin/contact localement ou via votre propre couche serveur.
