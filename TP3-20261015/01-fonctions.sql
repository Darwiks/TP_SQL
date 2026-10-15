-- =====================================================================
--  TP3 - Fonctions
--  A executer en root :
--      Get-Content -Raw .\01-fonctions.sql | mysql -u root -p mediatheque -t
--  Rejouable : chaque fonction est supprimee puis recreee.
--  Toutes les fonctions lisent des donnees : READS SQL DATA.
-- =====================================================================

USE mediatheque;

-- ---------------------------------------------------------------------
-- f_nb_emprunts_en_cours : nombre de documents non rendus d'un adherent
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS f_nb_emprunts_en_cours;
DELIMITER $$
CREATE FUNCTION f_nb_emprunts_en_cours(p_adherent_id INT UNSIGNED)
RETURNS INT
READS SQL DATA
BEGIN
  DECLARE v_nb INT DEFAULT 0;
  SELECT COUNT(*) INTO v_nb
    FROM emprunt
   WHERE adherent_id = p_adherent_id
     AND date_retour_reelle IS NULL;
  RETURN v_nb;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- f_penalites_dues : total des penalites non payees, 0.00 s'il n'y en a pas.
-- SUM() sur zero ligne vaut NULL, et NULL > 10 n'est ni vrai ni faux :
-- COALESCE garantit un vrai zero.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS f_penalites_dues;
DELIMITER $$
CREATE FUNCTION f_penalites_dues(p_adherent_id INT UNSIGNED)
RETURNS DECIMAL(8,2)
READS SQL DATA
BEGIN
  DECLARE v_total DECIMAL(8,2) DEFAULT 0.00;
  SELECT COALESCE(SUM(montant), 0.00) INTO v_total
    FROM penalite
   WHERE adherent_id = p_adherent_id
     AND payee = 0;
  RETURN v_total;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- f_jours_de_retard : jours de retard d'un emprunt, 0 s'il est dans les temps.
--   emprunt rendu    : comparaison avec date_retour_reelle
--   emprunt en cours : comparaison avec CURDATE()
--   emprunt inconnu  : 0
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS f_jours_de_retard;
DELIMITER $$
CREATE FUNCTION f_jours_de_retard(p_emprunt_id INT UNSIGNED)
RETURNS INT
READS SQL DATA
BEGIN
  DECLARE v_prevue DATE DEFAULT NULL;
  DECLARE v_reelle DATE DEFAULT NULL;

  SELECT date_retour_prevue, date_retour_reelle
    INTO v_prevue, v_reelle
    FROM emprunt
   WHERE id = p_emprunt_id;

  IF v_prevue IS NULL THEN
    RETURN 0;
  END IF;

  RETURN GREATEST(DATEDIFF(COALESCE(v_reelle, CURDATE()), v_prevue), 0);
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- Adherents ayant au moins un emprunt en cours, avec leurs penalites
-- ---------------------------------------------------------------------
SELECT a.id, a.nom, a.prenom,
       f_nb_emprunts_en_cours(a.id) AS en_cours,
       f_penalites_dues(a.id)       AS penalites_dues
  FROM adherent a
 WHERE f_nb_emprunts_en_cours(a.id) > 0
 ORDER BY en_cours DESC, a.nom;
