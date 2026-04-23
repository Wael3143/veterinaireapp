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
4. Copier tout le contenu et lancer le script dans Supabase
5. Aller dans `Authentication` > `Providers` > `Email`
6. Si vous voulez des connexions immediates, desactiver la confirmation email obligatoire
7. Definir votre email admin prive dans le navigateur avec `localStorage.setItem('vetpro-admin-email','votre-email-admin')`
8. Definir votre email de contact prive avec `localStorage.setItem('vetpro-contact-email','votre-email-contact')`
9. Verifier que votre email admin existe dans `Authentication` > `Users`
10. Se connecter avec le compte admin
11. Aller dans l'onglet `Approbations` pour approuver les autres utilisateurs

## Ce que fait Supabase

- Table `vetpro_access_requests` : stocke les demandes d'acces
- Table `vetpro_contact_messages` : stocke les messages envoyes depuis la page contacts
- Policies RLS : seuls les admins peuvent approuver et lire tous les messages

## Note importante

Le depot public ne contient plus d'email personnel ni de mot de passe admin. Configurez les emails admin/contact localement ou via votre propre couche serveur.
