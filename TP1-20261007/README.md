# TP1 — Sécuriser la base de la médiathèque

**Séance 1 · en binôme · sur machine · non noté**

## Objectif

Construire le plan de comptes de la médiathèque : trois rôles, quatre comptes, et la preuve — connexion à l'appui — que chacun peut exactement ce qu'il doit pouvoir, et rien de plus.

## Le contexte

La médiathèque municipale ouvre son application de gestion des prêts. Quatre acteurs vont travailler sur la même base :

| Qui | Ce qu'il doit pouvoir faire | Ce qu'il ne doit **pas** pouvoir faire |
|---|---|---|
| `app_media` — l'application web | Lire le catalogue, enregistrer et modifier des emprunts, des réservations et des pénalités, marquer un exemplaire comme sorti ou rentré | Supprimer quoi que ce soit, modifier le catalogue, lire les coordonnées des adhérents |
| `biblio_marie` — la bibliothécaire | Tout ce que fait l'application, plus la gestion complète des dossiers d'adhérents | Administrer le serveur, créer des comptes |
| `stagiaire` | Consulter le catalogue et la liste des adhérents | Voir un email, un téléphone ou une date de naissance ; écrire quoi que ce soit ; voir les emprunts |
| `analyste` | Lire les emprunts et le catalogue pour produire des statistiques | Lire la table `adherent`, écrire quoi que ce soit |

Trois de ces besoins se recoupent : c'est ce qui justifie des **rôles** plutôt que des privilèges accordés compte par compte.

## Point de départ

La base `mediatheque`, chargée avec les scripts du dossier `Base/` :

```
mysql -u root -p < Base/01-schema.sql
mysql -u root -p < Base/02-donnees.sql
```

Vérification : `SELECT COUNT(*) FROM mediatheque.adherent;` doit renvoyer 40.

## Ce qui vous est fourni

- `Base/01-schema.sql` — les sept tables de la médiathèque.
- `Base/02-donnees.sql` — le jeu de données : adhérents, ouvrages, emprunts en cours, retards, pénalités.
- `matrice-de-tests.md` — le tableau à remplir, une ligne par test.

Rien d'autre : les rôles, les comptes et les privilèges sont entièrement à écrire.

## Consignes

Tout tient dans **un seul fichier**, `01-roles-et-comptes.sql`, qui doit se rejouer du début à la fin. Commencez-le par les `DROP USER IF EXISTS` et `DROP ROLE IF EXISTS` : sans eux, la deuxième exécution s'arrête sur « compte déjà existant ».

**1. Les trois rôles**

Un rôle décrit un **métier**, pas une personne. Trois suffisent :

| Rôle | Ce qu'il porte |
|---|---|
| `role_catalogue` | `SELECT` sur `ouvrage`, `exemplaire`, `categorie` |
| `role_prets` | `SELECT`, `INSERT`, `UPDATE` sur `emprunt`, `reservation`, `penalite` — et **uniquement** `UPDATE` de la colonne `disponible` sur `exemplaire` |
| `role_adherents` | `SELECT`, `INSERT`, `UPDATE` sur `adherent` |

Aucun `DELETE` nulle part : un emprunt rendu reste dans l'historique, un adhérent parti est désactivé (`actif = 0`), il n'est pas effacé.

Le privilège sur une seule colonne s'écrit avec la liste des colonnes entre parenthèses, juste après le nom du privilège.

**2. Les quatre comptes**

Tous en `@'localhost'`. Des mots de passe qui passent la politique par défaut de MySQL : au moins 8 caractères, une majuscule, un chiffre, un caractère spécial.

Affectez ensuite les rôles, en suivant le tableau du contexte. Deux besoins ne sont couverts par aucun rôle et demandent un privilège accordé directement au compte :

- `app_media` doit lire `id`, `nom`, `prenom` et `actif` des adhérents — **et rien d'autre** de cette table ;
- `stagiaire` doit lire les adhérents **sans** `email`, `telephone` ni `date_naissance`.

Dans les deux cas, c'est un privilège de niveau colonne.

Enfin : un rôle accordé n'est pas un rôle actif. Ajoutez la ligne qui rend les rôles actifs **à chaque connexion** des comptes concernés — pas seulement pour la session en cours.

**3. Relire les droits, puis en retirer un**

Deux requêtes dont la sortie doit figurer dans votre rendu : `SHOW GRANTS` pour chacun des quatre comptes, puis les privilèges de niveau colonne de la base, lus dans `information_schema.column_privileges`.

Ensuite, le cycle complet sur un cas : la médiathèque décide que l'analyste n'a finalement pas besoin des réservations. Accordez-lui `SELECT` sur `reservation`, vérifiez avec `SHOW GRANTS`, retirez le privilège, vérifiez à nouveau. Les quatre commandes restent dans le script.

**4. Tester pour de vrai**

Ouvrez une connexion par compte et remplissez `matrice-de-tests.md` — douze tests. Chaque ligne attend un **OK** ou un **numéro d'erreur**, pas « ça marche ».

```
mysql -u stagiaire -p mediatheque
```

Quelques exemples de ce que vous allez y écrire :

```sql
-- en tant que stagiaire
SELECT email FROM adherent;                         -- attendu : ERROR 1143

-- en tant qu'app_media
UPDATE exemplaire SET disponible = 0 WHERE id = 1;  -- attendu : OK
UPDATE exemplaire SET etat = 'use'  WHERE id = 1;   -- attendu : ERROR 1143
```

**5. Bonus — si vous avez fini**

- L'analyste travaille depuis un poste du réseau, pas depuis le serveur. Créez `'analyste'@'192.168.1.%'` avec les mêmes privilèges, et expliquez en commentaire ce qui se passerait si `'analyste'@'%'` existait aussi.
- Le stage se termine. Écrivez les deux commandes possibles — verrouiller le compte, ou le supprimer — et indiquez en commentaire celle que vous choisiriez, et pourquoi.

## Points de vigilance

- **Un compte, c'est `'nom'@'machine'`.** `DROP USER 'stagiaire'` ne supprime pas `'stagiaire'@'localhost'` : ce sont deux comptes différents.
- **Un rôle accordé n'est pas actif.** Si un compte se connecte et ne voit rien alors que le `GRANT` est passé, c'est presque toujours ça. Vérifiez avec `SELECT CURRENT_ROLE();` dans sa session.
- **`SELECT *` cesse de fonctionner** dès qu'un compte n'a qu'un privilège de colonne. C'est normal, et c'est même le but : l'étoile inclurait les colonnes interdites.
- **`REVOKE` doit viser le même niveau que le `GRANT`.** Un privilège accordé sur `mediatheque.*` ne se retire pas table par table.
- **Pas de `FLUSH PRIVILEGES`.** C'est un réflexe hérité des anciennes versions : `GRANT` et `REVOKE` sont pris en compte immédiatement.
- **Ne travaillez jamais en root dans les tests.** Ouvrez une vraie connexion avec le compte testé, sinon vous testez les droits de root.

## Critères de réussite

- [ ] Les trois rôles existent et portent les privilèges du tableau
- [ ] Les quatre comptes existent, avec des mots de passe conformes
- [ ] Aucun `GRANT ALL`, aucun privilège au niveau `*.*`, aucun `DELETE` accordé
- [ ] Le privilège de colonne sur `exemplaire (disponible)` est en place, et le stagiaire ne peut lire ni `email`, ni `telephone`, ni `date_naissance`
- [ ] Les rôles sont actifs à la connexion, sans `SET ROLE` manuel
- [ ] Le cycle `GRANT` → vérification → `REVOKE` → vérification figure dans le script
- [ ] `matrice-de-tests.md` est remplie, avec les numéros d'erreur obtenus
- [ ] Le script se rejoue du début à la fin sans erreur, deux fois de suite
