-- =====================================================================
--  TP2 - Partie A : vues + bascule des droits du stagiaire
--  A executer en root :
--      Get-Content -Raw .\01-vues.sql | mysql -u root -p mediatheque --force -t
--
--  Rejouable : les vues utilisent CREATE OR REPLACE. Seul le REVOKE du
--  privilege de colonne echoue a la 2e execution (privilege deja retire,
--  ERROR 1141) : sans consequence, d'ou l'option --force.
-- =====================================================================

USE mediatheque;

-- ---------------------------------------------------------------------
-- 1) v_catalogue : un ouvrage par ligne, avec nb d'exemplaires et de
--    disponibles. LEFT JOIN pour garder les ouvrages SANS exemplaire ;
--    COALESCE car SUM() vaut NULL (et non 0) quand il n'y a aucune ligne.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_catalogue AS
SELECT o.id, o.titre, o.auteur, o.annee_publication,
       c.libelle AS categorie,
       COUNT(e.id)                         AS nb_exemplaires,
       COALESCE(SUM(e.disponible = 1), 0)  AS nb_disponibles
  FROM ouvrage o
  JOIN categorie c        ON c.id = o.categorie_id
  LEFT JOIN exemplaire e  ON e.ouvrage_id = o.id
 GROUP BY o.id, o.titre, o.auteur, o.annee_publication, c.libelle;

-- ---------------------------------------------------------------------
-- 2) v_adherent_public : adherents SANS email, telephone, date_naissance
--    (colonnes listees : pas de SELECT *, pour qu'une future colonne
--    confidentielle n'apparaisse pas par accident).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_adherent_public AS
SELECT id, nom, prenom, ville, date_inscription, actif
  FROM adherent;

-- ---------------------------------------------------------------------
-- 3) v_emprunt_en_cours : emprunts non rendus, avec jours de retard
--    (jours_retard negatif = encore dans les temps, c'est voulu).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_emprunt_en_cours AS
SELECT em.id AS emprunt_id, em.date_emprunt, em.date_retour_prevue,
       DATEDIFF(CURDATE(), em.date_retour_prevue) AS jours_retard,
       CONCAT(a.prenom, ' ', a.nom) AS adherent,
       o.titre, ex.code_barre
  FROM emprunt em
  JOIN adherent   a  ON a.id  = em.adherent_id
  JOIN exemplaire ex ON ex.id = em.exemplaire_id
  JOIN ouvrage    o  ON o.id  = ex.ouvrage_id
 WHERE em.date_retour_reelle IS NULL;

-- ---------------------------------------------------------------------
-- 4) v_retard : construite SUR v_emprunt_en_cours (jointures non recopiees).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_retard AS
SELECT emprunt_id, date_emprunt, date_retour_prevue, jours_retard,
       adherent, titre, code_barre
  FROM v_emprunt_en_cours
 WHERE jours_retard > 0;

-- ---------------------------------------------------------------------
-- Bascule des droits du stagiaire : il ne lit plus que des vues.
-- ---------------------------------------------------------------------
-- a) retirer le privilege de colonne du TP1 (meme niveau que le GRANT)
REVOKE SELECT (id, nom, prenom, ville, date_inscription, actif)
    ON mediatheque.adherent FROM 'stagiaire'@'localhost';

-- b) le role role_catalogue (TP1) donnait SELECT sur exemplaire : retire
REVOKE role_catalogue FROM 'stagiaire'@'localhost';

-- c) lui donner les vues
GRANT SELECT ON mediatheque.v_adherent_public  TO 'stagiaire'@'localhost';
GRANT SELECT ON mediatheque.v_catalogue        TO 'stagiaire'@'localhost';
GRANT SELECT ON mediatheque.v_emprunt_en_cours TO 'stagiaire'@'localhost';

-- Les vues s'executent avec les droits de leur createur (SQL SECURITY
-- DEFINER) : le stagiaire n'a besoin que du droit sur la vue, pas sur
-- les tables qu'elle interroge.

-- Verification : doit ne plus montrer que les 3 vues.
SHOW GRANTS FOR 'stagiaire'@'localhost';
