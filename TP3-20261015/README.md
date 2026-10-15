# TP3 — Faire vivre la médiathèque : emprunter et rendre

**Séance 3 · en binôme · sur machine · non noté**

## Objectif

Écrire les fonctions, les procédures et les triggers qui font fonctionner le prêt de la médiathèque, puis démontrer par un scénario de test que chaque règle métier est bien appliquée — y compris quand on essaie de la contourner.

## Le contexte

Jusqu'ici, emprunter un document se résume à un `INSERT` dans `emprunt`. Rien ne vérifie que l'adhérent existe, qu'il n'a pas déjà cinq documents chez lui, ni que l'exemplaire est disponible. Et rien ne met à jour `exemplaire.disponible`, qui est donc déjà faux dans la base dès qu'on écrit à la main.

Les règles de la médiathèque :

| Règle | Où elle doit vivre |
|---|---|
| L'adhérent existe et son inscription est active | procédure |
| L'exemplaire existe, est disponible et n'est pas hors service | procédure |
| Cinq documents maximum par adhérent | procédure |
| Pas plus de 10 € de pénalités impayées | procédure |
| Le prêt dure 14 jours | trigger (valeur calculée) |
| Un exemplaire sorti n'est pas disponible | trigger (invariant) |
| Retard facturé 0,20 € par jour | procédure (c'est un tarif, donc une décision) |
| Toute écriture sur `emprunt` est journalisée | trigger (traçabilité) |

La ligne de partage est le fil conducteur de la séance : **un invariant de données va dans un trigger, une opération métier va dans une procédure.**

## Point de départ

La base `mediatheque` avec les vues et les index du TP2. Si vous repartez de zéro :

```
mysql -u root -p < Base/01-schema.sql
mysql -u root -p < Base/02-donnees.sql
```

La mise en volume n'est pas nécessaire pour ce TP — et vous fera gagner du temps si vous l'omettez.

## Ce qui vous est fourni

- `scenario-de-test.md` — la trame du fichier de tests à produire.

Les fonctions, les procédures et les triggers sont entièrement à écrire.

## Consignes

**1. `01-fonctions.sql` — trois fonctions**

| Fonction | Renvoie |
|---|---|
| `f_nb_emprunts_en_cours(p_adherent_id)` | le nombre de documents non rendus |
| `f_penalites_dues(p_adherent_id)` | le total des pénalités non payées, **0.00 s'il n'y en a aucune** |
| `f_jours_de_retard(p_emprunt_id)` | le nombre de jours de retard, 0 si l'emprunt est dans les temps |

Trois points de syntaxe :

- une fonction déclare ce qu'elle fait au serveur : ces trois-là lisent des données, donc `READS SQL DATA` ;
- `SUM()` sur zéro ligne renvoie `NULL`, pas `0` — et `NULL > 10` n'est ni vrai ni faux : `f_penalites_dues` doit renvoyer un vrai zéro ;
- `f_jours_de_retard` doit fonctionner pour un emprunt rendu (comparaison avec `date_retour_reelle`) comme pour un emprunt en cours (comparaison avec `CURDATE()`).

Terminez par une requête qui liste les adhérents ayant au moins un emprunt en cours, avec leurs pénalités, en utilisant vos trois fonctions.

**2. `02-procedures.sql` — `p_emprunter`**

```sql
CALL p_emprunter(p_code_barre, p_adherent_id, @emprunt_id);
```

Les quatre règles de la procédure, dans l'ordre du tableau. Chaque refus lève une erreur avec `SIGNAL SQLSTATE '45000'` et un message que l'utilisateur de l'application pourra lire tel quel — pas « erreur 3 ».

La procédure doit aussi :

- être encadrée par `START TRANSACTION` / `COMMIT` ;
- installer un `EXIT HANDLER FOR SQLEXCEPTION` qui fait `ROLLBACK` puis `RESIGNAL` ;
- renvoyer l'identifiant du nouvel emprunt dans son paramètre `OUT` ;
- **ne pas** toucher à `exemplaire.disponible` : c'est le travail du trigger de la consigne 4.

Attention au cas « code-barres inconnu » : un `SELECT … INTO` qui ne trouve rien laisse la variable inchangée. Déclarez-la avec `DEFAULT NULL` et testez `IS NULL`.

**3. `02-procedures.sql` — `p_rendre` et `p_bilan_adherent`**

`p_rendre(p_code_barre)` : retrouve l'emprunt en cours de cet exemplaire, l'ancre à la date du jour, et crée une pénalité de 0,20 € par jour de retard s'il y a lieu. Si aucun emprunt n'est en cours pour ce code-barres, elle refuse avec un message explicite. Elle se termine par un `SELECT` qui renvoie l'identifiant de l'emprunt, les jours de retard et le montant facturé.

`p_bilan_adherent(p_adherent_id)` : renvoie **trois** jeux de résultats — la fiche de l'adhérent (avec vos fonctions), la liste de ses emprunts en cours, et son nombre total d'emprunts depuis l'inscription. C'est la démonstration de ce qu'une fonction ne sait pas faire.

**4. `03-triggers.sql` — trois triggers**

Créez d'abord la table d'audit :

```sql
CREATE TABLE IF NOT EXISTS journal_action (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  table_cible VARCHAR(40)     NOT NULL,
  operation   VARCHAR(10)     NOT NULL,
  cle         VARCHAR(40)     NOT NULL,
  auteur      VARCHAR(100)    NOT NULL,
  horodatage  DATETIME        NOT NULL,
  details     VARCHAR(255)        NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB;
```

Puis :

| Trigger | Ce qu'il fait |
|---|---|
| `BEFORE INSERT ON emprunt` | remplit `date_emprunt` et `date_retour_prevue` si elles sont absentes (14 jours), et refuse une date de retour antérieure à la date d'emprunt |
| `AFTER INSERT ON emprunt` | passe l'exemplaire à indisponible et journalise |
| `AFTER UPDATE ON emprunt` | détecte le **passage** de `date_retour_reelle` de `NULL` à une date : rend l'exemplaire disponible et journalise |

Pour le troisième : comparez `OLD` et `NEW`. Sans cette comparaison, n'importe quelle modification de la ligne d'emprunt rendrait l'exemplaire disponible — même un simple changement de date.

**5. `04-tests.sql` — le scénario**

Reprenez `scenario-de-test.md` et écrivez le script correspondant. Les cas qui doivent échouer restent en commentaire dans le fichier livré, avec le message d'erreur obtenu juste en dessous — pour que le script se rejoue d'un bout à l'autre.

Le test T7 est le plus intéressant : un `INSERT` direct dans `emprunt`, sans passer par la procédure, doit quand même produire une date de retour à 14 jours et un exemplaire indisponible. C'est la démonstration de ce que le trigger apporte et que la procédure, seule, n'apporterait pas.

**6. Bonus — EXECUTE plutôt qu'INSERT**

Retirez à `app_media` les privilèges `INSERT` et `UPDATE` sur `emprunt`, et donnez-lui `EXECUTE` sur vos deux procédures. Vérifiez, connecté avec ce compte, que `CALL p_emprunter(...)` fonctionne et qu'un `INSERT` direct est refusé. Expliquez en commentaire pourquoi c'est possible.

**7. Bonus — le trigger qui coûte cher**

Chronométrez `Base/03-volume.sql` (200 000 insertions) avec vos triggers en place, puis après les avoir supprimés. Concluez.

## Points de vigilance

- **`DELIMITER` n'est pas du SQL.** C'est une instruction au client. Sans lui, le premier `;` interne coupe votre procédure en deux et vous obtenez une erreur de syntaxe incompréhensible.
- **Toutes les `DECLARE` en tête de bloc**, avant la première instruction, sinon erreur 1064.
- **Préfixez vos paramètres** (`p_`) et vos variables (`v_`). Un paramètre qui porte le même nom qu'une colonne fait silencieusement gagner la colonne : `WHERE adherent_id = adherent_id` est toujours vrai.
- **Un trigger ne peut pas écrire dans la table qui l'a déclenché.** Pour modifier la ligne en cours d'insertion, c'est `SET NEW.colonne` en `BEFORE`, jamais un `UPDATE`.
- **Un trigger ne peut pas modifier une table que l'instruction en cours est en train de lire.** `INSERT INTO emprunt (…) SELECT … FROM exemplaire …` échoue en erreur 1442, parce que le trigger veut écrire dans `exemplaire`. Le même `INSERT … VALUES (…)` passe sans problème.
- **Un trigger ne fait ni `COMMIT` ni `ROLLBACK`** : il fait partie de la transaction de l'ordre qui l'a déclenché. Un `SIGNAL` dans un trigger annule l'écriture d'origine.
- **Ne dupliquez pas une règle** entre la procédure et le trigger. Si le quota est vérifié aux deux endroits, vous aurez un jour deux réponses différentes.
- **`SIGNAL` sans `MESSAGE_TEXT`** produit un message vide : l'application ne saura pas quoi afficher.
- **Testez avec une connexion autre que root** pour le bonus 6 : sinon vous testez les droits de root.

## Critères de réussite

- [ ] Les trois fonctions existent, déclarent `READS SQL DATA`, et `f_penalites_dues` renvoie `0.00` et non `NULL`
- [ ] `p_emprunter` applique les quatre règles, dans un ordre justifié
- [ ] Chaque refus lève `SQLSTATE '45000'` avec un message lisible par un utilisateur
- [ ] `p_emprunter` gère sa transaction et son handler d'erreur
- [ ] `p_emprunter` renvoie l'identifiant créé dans un paramètre `OUT`
- [ ] `p_rendre` crée la pénalité au bon montant, et seulement en cas de retard
- [ ] `p_bilan_adherent` renvoie bien trois jeux de résultats
- [ ] Les trois triggers existent, avec le bon moment et le bon événement
- [ ] Le trigger `AFTER UPDATE` compare `OLD` et `NEW` et ne se déclenche que sur un vrai retour
- [ ] `exemplaire.disponible` est maintenu par le trigger, pas par la procédure
- [ ] Un `INSERT` direct dans `emprunt` produit malgré tout une date de retour et un exemplaire indisponible
- [ ] Le scénario de test couvre les neuf cas, avec les messages d'erreur obtenus
- [ ] Les scripts se rejouent du début à la fin
