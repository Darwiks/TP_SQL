# TP2 — Vues de sécurité et chasse aux requêtes lentes

**Séance 2 · en binôme · sur machine · non noté**

## Objectif

Donner à la médiathèque les vues dont elle a besoin au quotidien, basculer les droits du stagiaire sur ces vues plutôt que sur les tables, puis rendre trois requêtes rapides — en prouvant le gain par un `EXPLAIN` avant et après.

## Point de départ

La base `mediatheque` et les comptes du TP1. Si vous repartez de zéro :

```
mysql -u root -p < Base/01-schema.sql
mysql -u root -p < Base/02-donnees.sql
mysql -u root -p < TP1 Corrige/01-roles-et-comptes.sql     # publié après la séance 1
```

Puis, **pour la partie B uniquement**, la mise en volume :

```
mysql -u root -p < Base/03-volume.sql
```

Ce dernier script ajoute 200 000 emprunts d'archive. Comptez une à deux minutes. Sans lui, toutes vos requêtes répondront en 0 ms et aucun index ne servira à rien : c'est la partie B entière qui perd son sens.

## Ce qui vous est fourni

- `Base/03-volume.sql` — la mise en volume de la table `emprunt`.
- `rapport-index.md` — le tableau avant / après à remplir.

Les vues et les index sont entièrement à écrire.

---

# Partie A — Les vues

**1. `01-vues.sql` — les quatre vues du quotidien**

| Vue | Ce qu'elle expose |
|---|---|
| `v_catalogue` | Un ouvrage par ligne : titre, auteur, année, libellé de la catégorie, nombre d'exemplaires et nombre d'exemplaires disponibles |
| `v_adherent_public` | Les adhérents **sans** `email`, `telephone` ni `date_naissance` |
| `v_emprunt_en_cours` | Les emprunts non rendus : identifiant, dates, jours de retard, nom complet de l'adhérent, titre de l'ouvrage, code-barres |
| `v_retard` | Les seuls emprunts en cours dont la date de retour prévue est dépassée — **construite sur `v_emprunt_en_cours`**, pas en recopiant ses jointures |

Pour `v_catalogue`, `nb_disponibles` se calcule sans sous-requête : `SUM(e.disponible = 1)` compte les lignes où la condition est vraie. Un ouvrage dont aucun exemplaire n'a été saisi doit quand même apparaître, avec 0 — pensez au type de jointure.

Pour `v_emprunt_en_cours`, les jours de retard se calculent avec `DATEDIFF(CURDATE(), date_retour_prevue)` : la valeur est négative quand l'emprunt est encore dans les temps, et c'est bien ce qu'on veut.

**2. Basculer les droits du stagiaire**

Au TP1, le stagiaire avait un privilège de colonne sur `adherent`. Retirez-le, et donnez-lui à la place l'accès aux vues `v_adherent_public`, `v_catalogue` et `v_emprunt_en_cours`.

Vérifiez ensuite, connecté en `stagiaire` :

```sql
SELECT * FROM v_adherent_public;   -- doit fonctionner, et l'étoile fonctionne à nouveau
SELECT * FROM adherent;            -- doit être refusé
```

Le stagiaire n'a **aucun** privilège sur `adherent`, `emprunt` ou `exemplaire`, et lit pourtant trois vues qui les interrogent. Expliquez en commentaire, en une phrase, pourquoi cela fonctionne.

**3. `02-vue-modifiable.sql` — une vue par laquelle on écrit**

Créez `v_adherent_lyon` : les adhérents dont la ville est `'Lyon'`, avec `WITH CHECK OPTION`.

Puis, dans le même script, les trois essais suivants — les deux derniers doivent échouer, et l'erreur fait partie du résultat attendu :

1. insérer un adhérent lyonnais par la vue : doit fonctionner, et la ligne doit apparaître dans `adherent` ;
2. insérer un adhérent de Bron par la vue : doit échouer ;
3. faire un `UPDATE` sur `v_catalogue` : doit échouer.

Relevez les deux numéros d'erreur et expliquez, pour chacun, ce que le serveur refuse exactement.

**4. Quelles vues sont modifiables ?**

Interrogez `information_schema.views` et relevez la colonne `is_updatable` pour vos cinq vues. Justifiez en commentaire, pour chaque `NO`, ce qui empêche la modification.

---

# Partie B — Les index

Tous les `EXPLAIN` de cette partie se font sur la table `emprunt` **après** la mise en volume.

**5. `03-index.sql` — mesurer avant**

Lancez `EXPLAIN` sur les trois requêtes suivantes et notez, dans `rapport-index.md`, les colonnes `type`, `key`, `rows` et `Extra` :

```sql
-- R1 : les emprunts d'une journée
SELECT * FROM emprunt WHERE date_emprunt = '2024-03-12';

-- R2 : les emprunts en cours (c'est la requête derrière v_emprunt_en_cours)
SELECT * FROM emprunt WHERE date_retour_reelle IS NULL;

-- R3 : l'historique récent d'un adhérent
SELECT id, date_emprunt FROM emprunt
 WHERE adherent_id = 12 AND date_emprunt >= '2025-01-01';
```

Comptez aussi, pour chacune, le nombre de lignes réellement renvoyées. C'est l'écart entre ce nombre et `rows` qui dit si un index a une chance de servir.

**6. Poser les index — un par requête, et justifié**

Créez l'index qui répond à R1, celui qui répond à R2, et l'index **composite** qui répond à R3. Pour ce dernier, l'ordre des colonnes n'est pas libre : justifiez-le en commentaire.

Après chaque création : `ANALYZE TABLE emprunt;`, puis relancez l'`EXPLAIN` et remplissez la colonne « après » du rapport.

**7. Le préfixe gauche**

Avec l'index composite en place, lancez :

```sql
EXPLAIN SELECT id FROM emprunt WHERE adherent_id = 12;
EXPLAIN SELECT id FROM emprunt WHERE date_emprunt >= '2025-01-01';
```

L'une des deux profite de l'index composite, l'autre non. Dites laquelle, et pourquoi.

**8. L'index couvrant**

Comparez ces deux requêtes :

```sql
EXPLAIN SELECT adherent_id, date_emprunt FROM emprunt WHERE adherent_id = 12;
EXPLAIN SELECT adherent_id, date_emprunt, exemplaire_id FROM emprunt WHERE adherent_id = 12;
```

Une mention disparaît de la colonne `Extra`. Laquelle, et qu'est-ce que le serveur doit faire en plus dans le second cas ?

**9. La requête qu'il faut réécrire**

```sql
SELECT COUNT(*) FROM emprunt WHERE YEAR(date_emprunt) = 2024;
```

Elle n'utilise pas correctement l'index sur `date_emprunt`. Réécrivez-la pour qu'elle donne **exactement le même résultat** en utilisant l'index, et montrez les deux `EXPLAIN`.

**10. Le prix payé**

Relevez le poids des données et celui des index de `emprunt` dans `information_schema.tables`, avant et après vos créations. Concluez en une phrase.

**11. Bonus — l'index qui résiste**

Essayez de supprimer l'index composite créé en 6. Que se passe-t-il ? Pourquoi ? Quelle propriété d'InnoDB explique ce refus ?

**12. Bonus — la vue lente**

`v_retard` est construite sur `v_emprunt_en_cours`. Lancez `EXPLAIN SELECT * FROM v_retard;` : quelles tables apparaissent ? Vos index de la partie B servent-ils ?

## Points de vigilance

- **Sans `ANALYZE TABLE`, l'optimiseur se trompe.** Après une grosse insertion ou un nouvel index, les statistiques sont périmées et le plan choisi peut être aberrant.
- **`rows` est une estimation**, pas un décompte. Elle suffit pour comparer un avant et un après, mais elle varie légèrement d'une exécution à l'autre.
- **Vos chiffres doivent être ceux du corrigé.** L'archive est générée avec un tirage aléatoire *initialisé* : tout le monde obtient la même base. Un `rows` qui s'écarte de quelques unités est normal (c'est une estimation) ; un ordre de grandeur différent veut dire que la mise en volume n'a pas été chargée.
- **Une clé étrangère est déjà indexée.** Inutile de créer un index sur `exemplaire_id` seul : regardez `information_schema.statistics` avant de poser quoi que ce soit.
- **Une vue ne s'indexe pas.** On indexe les colonnes des tables qu'elle interroge.
- **`CREATE OR REPLACE VIEW`** rend le script rejouable ; `CREATE INDEX` ne l'est pas. Prévoyez un `DROP INDEX … ON …` en tête de script, ou acceptez l'erreur « index déjà existant » à la deuxième exécution et dites-le en commentaire.
- **`SELECT *` dans une vue** est une mauvaise idée : le jour où une colonne est ajoutée à la table, elle apparaît dans la vue, y compris si elle est confidentielle.

## Critères de réussite

- [ ] Les cinq vues existent et renvoient des données cohérentes
- [ ] `v_retard` est construite sur `v_emprunt_en_cours`, sans recopier ses jointures
- [ ] Un ouvrage sans exemplaire apparaît dans `v_catalogue` avec 0
- [ ] Le stagiaire lit les trois vues et n'a plus aucun privilège sur `adherent`
- [ ] `WITH CHECK OPTION` refuse bien l'insertion hors périmètre, avec le numéro d'erreur relevé
- [ ] `is_updatable` est relevé pour les cinq vues, et chaque `NO` est justifié
- [ ] `rapport-index.md` est rempli : `type`, `key`, `rows`, `Extra`, avant et après
- [ ] Chaque index créé est justifié par une requête précise, en commentaire
- [ ] L'ordre des colonnes de l'index composite est expliqué
- [ ] La requête avec `YEAR()` est réécrite, et les deux `EXPLAIN` figurent au rendu
- [ ] Les scripts se rejouent du début à la fin
