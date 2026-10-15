-- =====================================================================
--  TP2 - Partie A : vue modifiable v_adherent_lyon + 3 essais
--  A executer en root, AVEC --force (deux instructions doivent echouer) :
--      Get-Content -Raw .\02-vue-modifiable.sql | mysql -u root -p mediatheque --force -t
-- =====================================================================

USE mediatheque;

-- Nettoyage d'une vue creee par erreur (faute de frappe "adherant").
DROP VIEW IF EXISTS v_adherant_lyon;

-- Toutes les colonnes NOT NULL sans valeur par defaut de adherent y figurent
-- (nom, prenom, email, ville, date_inscription), sinon l'INSERT serait impossible.
CREATE OR REPLACE VIEW v_adherent_lyon AS
SELECT id, nom, prenom, email, telephone, date_naissance,
       ville, date_inscription, actif
  FROM adherent
 WHERE ville = 'Lyon'
WITH CHECK OPTION;

-- Nettoyage pour pouvoir rejouer (l'email est UNIQUE).
DELETE FROM adherent WHERE email IN ('test.lyon@example.fr','test.bron@example.fr');

-- Essai 1 : doit MARCHER, et la ligne apparait dans adherent.
INSERT INTO v_adherent_lyon (nom, prenom, email, ville, date_inscription)
VALUES ('Test', 'Lyon', 'test.lyon@example.fr', 'Lyon', CURDATE());
SELECT id, nom, ville FROM adherent WHERE email = 'test.lyon@example.fr';

-- Essai 2 : doit ECHOUER, la ville est hors du perimetre de la vue.
INSERT INTO v_adherent_lyon (nom, prenom, email, ville, date_inscription)
VALUES ('Test', 'Bron', 'test.bron@example.fr', 'Bron', CURDATE());
-- ERROR 1369 (HY000): CHECK OPTION failed 'mediatheque.v_adherent_lyon'
-- (la ligne inseree ne satisferait pas le WHERE ville = 'Lyon' de la vue)

-- Essai 3 : doit ECHOUER, v_catalogue n'est pas modifiable.
UPDATE v_catalogue SET titre = 'X' WHERE id = 1;
-- ERROR 1288 (HY000): The target table v_catalogue of the UPDATE is not updatable

-- ---------------------------------------------------------------------
-- Consigne 4 : quelles vues sont modifiables ?
-- ---------------------------------------------------------------------
SELECT table_name, is_updatable
  FROM information_schema.views
 WHERE table_schema = 'mediatheque';

/*
+--------------------+--------------+
| TABLE_NAME         | IS_UPDATABLE |
+--------------------+--------------+
| v_catalogue        | NO           |
| v_adherent_public  | YES          |
| v_emprunt_en_cours | YES          |
| v_retard           | YES          |
| v_adherent_lyon    | YES          |
+--------------------+--------------+

Justifications :
- v_catalogue = NO : la vue contient un GROUP BY et des agregats (COUNT, SUM).
  Une ligne de la vue resume plusieurs lignes de exemplaire : elle ne correspond
  pas a une ligne unique d'une table, MySQL ne sait pas laquelle modifier.
- v_adherent_public = YES : simple SELECT de colonnes d'une seule table, sans
  agregat, DISTINCT ni UNION (chaque ligne de la vue = une ligne d'adherent).
- v_adherent_lyon = YES : meme chose avec un WHERE ; WITH CHECK OPTION
  controle en plus que les ecritures restent dans le perimetre (ville = 'Lyon').
- v_emprunt_en_cours = YES : MySQL accepte une vue sur jointures (sans GROUP BY
  ni agregat) comme modifiable, tant qu'une seule table sous-jacente est
  modifiee par instruction. Colonnes calculees (DATEDIFF, CONCAT) non modifiables.
- v_retard = YES : construite sur v_emprunt_en_cours avec un simple WHERE, elle
  herite de sa modifiabilite.
*/
