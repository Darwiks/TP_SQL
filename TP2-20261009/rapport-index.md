# TP2 — Rapport d'optimisation

> Les chiffres attendus sont des **ordres de grandeur** : l'archive est générée
> aléatoirement, les vôtres seront proches sans être identiques.

Table `emprunt` : 200 130 lignes (relevé par `SELECT COUNT(*)` avant les index).

## Avant / après

Pour chaque requête : le plan avant tout index, puis le plan après l'index que vous avez posé.

### R1 — les emprunts d'une journée

```sql
SELECT * FROM emprunt WHERE date_emprunt = '2024-03-12';
```

| | `type` | `key` | `rows` | `Extra` |
|---|---|---|---|---|
| avant | ALL | NULL | 194891 | Using where |
| après | ref | idx_emprunt_date | 104 | NULL |

- Index créé : `CREATE INDEX idx_emprunt_date ON emprunt (date_emprunt);`
- Lignes réellement renvoyées : `104`
- Une phrase de conclusion : sans index MySQL lisait toute la table (~195 000 lignes) pour en renvoyer 104 ; avec l'index il va directement aux 104 lignes, et l'estimation `rows` est exacte.

### R2 — les emprunts en cours

```sql
SELECT * FROM emprunt WHERE date_retour_reelle IS NULL;
```

| | `type` | `key` | `rows` | `Extra` |
|---|---|---|---|---|
| avant | ALL | NULL | 194891 | Using where |
| après | ref | idx_emprunt_retour_reelle | 30 | Using index condition |

- Index créé : `CREATE INDEX idx_emprunt_retour_reelle ON emprunt (date_retour_reelle);`
- Lignes réellement renvoyées : `30`
- Une phrase de conclusion : presque tous les emprunts sont rendus, seules 30 lignes ont `NULL` : l'index est très sélectif et on passe de ~195 000 lignes lues à 30.

### R3 — l'historique récent d'un adhérent

```sql
SELECT id, date_emprunt FROM emprunt
 WHERE adherent_id = 12 AND date_emprunt >= '2025-01-01';
```

| | `type` | `key` | `rows` | `Extra` |
|---|---|---|---|---|
| avant | ref | fk_emprunt_adherent | 5027 | Using where |
| après | range | idx_emprunt_adherent_date | 723 | Using where; Using index |

- Index créé : `CREATE INDEX idx_emprunt_adherent_date ON emprunt (adherent_id, date_emprunt);`
- Lignes réellement renvoyées : `723` (relevé par `SELECT COUNT(*)`)
- Pourquoi les colonnes sont-elles dans cet ordre, et pas dans l'autre ? L'égalité (`adherent_id = 12`) doit venir en premier et la plage (`date_emprunt >= ...`) en dernier : MySQL se positionne sur l'adhérent 12 puis parcourt ses dates dans l'ordre, ce qui ne lit que 723 entrées. Dans l'ordre inverse `(date_emprunt, adherent_id)`, la plage sur la première colonne empêcherait d'utiliser `adherent_id` pour affiner. L'index contient aussi `id` (clé primaire) : il couvre la requête (`Using index`), sans lire la table.

## Le préfixe gauche (consigne 7)

| Requête | L'index composite sert-il ? | Pourquoi |
|---|---|---|
| `WHERE adherent_id = 12` | Oui : `key = idx_emprunt_adherent_date`, type `ref`, rows 5027, `Using index` | `adherent_id` est la **première** colonne du composite (préfixe gauche). |
| `WHERE date_emprunt >= '2025-01-01'` | Non : MySQL choisit `idx_emprunt_date` (type `range`, rows 55224, `Using where; Using index`) | `date_emprunt` est la 2e colonne et la 1re n'est pas filtrée : le composite ne permet pas de se positionner. C'est l'index simple de R1 qui sert. |

## L'index couvrant (consigne 8)

- Mention présente dans le premier `Extra` : `Using index`
- Elle disparaît dans le second parce que : `exemplaire_id` n'est pas dans l'index composite (`adherent_id`, `date_emprunt` + `id`). Pour chaque ligne trouvée, MySQL doit aller lire la ligne complète dans la table (via la clé primaire), soit un accès de plus par ligne ; `Extra` vaut alors `NULL`.

## La requête réécrite (consigne 9)

```sql
-- version d'origine
SELECT COUNT(*) FROM emprunt WHERE YEAR(date_emprunt) = 2024;
-- type : index   rows : 199875   (key = idx_emprunt_date, Using where; Using index)

-- version réécrite
SELECT COUNT(*) FROM emprunt
 WHERE date_emprunt >= '2024-01-01' AND date_emprunt < '2025-01-01';
-- type : range   rows : 22203    (key = idx_emprunt_adherent_date, Using where; Using index for skip scan)
```

Remarque : avant la création des index, la version d'origine faisait un `type = ALL` (194891 lignes). Une fois `idx_emprunt_date` posé, MySQL parcourt tout l'index (`type = index`, ~200 000 entrées) parce que `YEAR()` empêche de se positionner sur une plage ; c'est plus léger qu'une lecture de la table, mais cela reste un parcours complet. La version réécrite compare directement la colonne et ne lit plus qu'une plage (~22 000 estimées).

Les deux renvoient bien le même nombre : `43015`

## Le prix des index (consigne 10)

| | `donnees_mo` | `index_mo` |
|---|---|---|
| avant | 8.52 | 10.03 |
| après | 8.52 | 18.06 |

Conclusion : les 3 index font passer l'espace d'index de 10 à 18 Mo (+8 Mo), soit plus que les données elles-mêmes (8.5 Mo). Ils ralentissent aussi chaque `INSERT`/`UPDATE`/`DELETE`, qui doit les maintenir à jour. En échange, les lectures passent de ~195 000 lignes lues à quelques dizaines ou centaines : on n'indexe que ce que les requêtes utilisent vraiment.

## Bonus

- Consigne 11 — l'index qu'on ne peut pas supprimer : `DROP INDEX idx_emprunt_adherent_date ON emprunt;` donne `ERROR 1553 (HY000): Cannot drop index 'idx_emprunt_adherent_date': needed in a foreign key constraint`. InnoDB exige un index sur `adherent_id` pour la clé étrangère `fk_emprunt_adherent`. En créant le composite (dont `adherent_id` est la première colonne), l'index implicite `fk_emprunt_adherent` a été remplacé silencieusement : il n'apparaît plus dans `information_schema.statistics` après la création. C'est désormais le composite qui garantit la contrainte, on ne peut donc plus le supprimer.
- Consigne 12 — `EXPLAIN` sur `v_retard` : 4 tables visitées, `em` (emprunt), `a` (adherent), `ex` (exemplaire) et `o` (ouvrage), car MySQL fusionne la vue avec `v_emprunt_en_cours`. Pour `emprunt` : `type = ref`, `key = idx_emprunt_retour_reelle`, rows 30 (`Using index condition; Using where`) : l'index posé pour R2 sert donc aussi à la vue. Les trois autres tables sont lues par `eq_ref` sur leur clé primaire (1 ligne chacune). On n'indexe pas une vue : on indexe les tables sous-jacentes.
