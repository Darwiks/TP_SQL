-- =====================================================================
--  TP3 - Procedures : emprunter, rendre, bilan
--  A executer en root, APRES 01-fonctions.sql et 03-triggers.sql :
--      Get-Content -Raw .\02-procedures.sql | mysql -u root -p mediatheque -t
--  Rejouable : DROP PROCEDURE IF EXISTS avant chaque CREATE.
--
--  Regle du TP : une OPERATION / DECISION metier va dans une procedure.
--  Pas d'accents dans les messages (PowerShell les abime).
-- =====================================================================

USE mediatheque;

-- ---------------------------------------------------------------------
-- p_emprunter(code-barres, adherent, OUT id de l'emprunt)
--
-- Ordre des regles : de la plus fondamentale a la plus couteuse.
--   1. l'adherent existe et est actif  (inutile de compter les emprunts d'un
--      inconnu)
--   2. l'exemplaire existe, est en service, est libre
--   3. quota de 5 documents  (un simple COUNT)
--   4. penalites impayees <= 10 EUR  (un SUM)
-- La procedure ne touche NI aux dates NI a exemplaire.disponible : ce sont
-- les invariants du trigger (le NULL explicite signifie "calcule-les").
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS p_emprunter;
DELIMITER $$
CREATE PROCEDURE p_emprunter(
    IN  p_code_barre  VARCHAR(20),
    IN  p_adherent_id INT UNSIGNED,
    OUT p_emprunt_id  INT UNSIGNED)
BEGIN
  -- DEFAULT NULL : un SELECT ... INTO qui ne trouve rien laisse la
  -- variable inchangee, on teste ensuite IS NULL.
  DECLARE v_actif         TINYINT      DEFAULT NULL;
  DECLARE v_exemplaire_id INT UNSIGNED DEFAULT NULL;
  DECLARE v_disponible    TINYINT      DEFAULT NULL;
  DECLARE v_etat          VARCHAR(20)  DEFAULT NULL;

  -- Toute erreur annule la transaction puis est renvoyee telle quelle.
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SET p_emprunt_id = NULL;
  START TRANSACTION;

  -- Regle 1 : adherent existant et actif.
  -- FOR UPDATE : deux emprunts simultanes du meme adherent ne peuvent pas
  -- depasser le quota.
  SELECT actif INTO v_actif
    FROM adherent
   WHERE id = p_adherent_id
     FOR UPDATE;
  IF v_actif IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Adherent inconnu.';
  END IF;
  IF v_actif = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Inscription inactive : emprunt impossible.';
  END IF;

  -- Regle 2 : exemplaire existant, en service, disponible.
  SELECT id, disponible, etat
    INTO v_exemplaire_id, v_disponible, v_etat
    FROM exemplaire
   WHERE code_barre = p_code_barre
     FOR UPDATE;
  IF v_exemplaire_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Code-barres inconnu.';
  END IF;
  IF v_etat = 'hors_service' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Exemplaire hors service.';
  END IF;
  IF v_disponible = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Exemplaire deja emprunte.';
  END IF;

  -- Regle 3 : cinq documents maximum.
  IF f_nb_emprunts_en_cours(p_adherent_id) >= 5 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Quota atteint : 5 documents maximum.';
  END IF;

  -- Regle 4 : pas plus de 10 EUR de penalites impayees.
  IF f_penalites_dues(p_adherent_id) > 10 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Penalites impayees superieures a 10 euros.';
  END IF;

  INSERT INTO emprunt (exemplaire_id, adherent_id, date_emprunt, date_retour_prevue)
  VALUES (v_exemplaire_id, p_adherent_id, NULL, NULL);

  -- Les INSERT faits par un trigger (journal_action) ne modifient pas cette valeur.
  SET p_emprunt_id = LAST_INSERT_ID();

  COMMIT;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- p_rendre(code-barres)
-- Le tarif (0,20 EUR par jour) est ici et pas dans un trigger : c'est une
-- decision metier, pas un invariant. Le retard est calcule AVANT de clore
-- l'emprunt : tant qu'il est en cours, la fonction compare a CURDATE().
-- exemplaire.disponible est remis a 1 par le trigger AFTER UPDATE.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS p_rendre;
DELIMITER $$
CREATE PROCEDURE p_rendre(IN p_code_barre VARCHAR(20))
BEGIN
  DECLARE v_emprunt_id  INT UNSIGNED DEFAULT NULL;
  DECLARE v_adherent_id INT UNSIGNED DEFAULT NULL;
  DECLARE v_retard      INT          DEFAULT 0;
  DECLARE v_montant     DECIMAL(6,2) DEFAULT 0.00;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT em.id, em.adherent_id
    INTO v_emprunt_id, v_adherent_id
    FROM emprunt em
    JOIN exemplaire ex ON ex.id = em.exemplaire_id
   WHERE ex.code_barre = p_code_barre
     AND em.date_retour_reelle IS NULL
   LIMIT 1
     FOR UPDATE;

  IF v_emprunt_id IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Aucun emprunt en cours pour ce code-barres.';
  END IF;

  SET v_retard  = f_jours_de_retard(v_emprunt_id);
  SET v_montant = v_retard * 0.20;

  UPDATE emprunt
     SET date_retour_reelle = CURDATE()
   WHERE id = v_emprunt_id;

  IF v_retard > 0 THEN
    INSERT INTO penalite (adherent_id, emprunt_id, montant, motif, date_creation, payee)
    VALUES (v_adherent_id, v_emprunt_id, v_montant,
            CONCAT('Retour avec ', v_retard, ' jour(s) de retard'),
            CURDATE(), 0);
  END IF;

  COMMIT;

  SELECT v_emprunt_id AS emprunt_id,
         v_retard     AS jours_retard,
         v_montant    AS montant_facture;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- p_bilan_adherent(adherent) : TROIS jeux de resultats.
-- C'est ce qu'une fonction ne sait pas faire (une valeur, un seul resultat).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS p_bilan_adherent;
DELIMITER $$
CREATE PROCEDURE p_bilan_adherent(IN p_adherent_id INT UNSIGNED)
BEGIN
  -- 1) la fiche de l'adherent, avec les fonctions
  SELECT a.id, a.nom, a.prenom, a.ville, a.actif,
         f_nb_emprunts_en_cours(a.id) AS emprunts_en_cours,
         f_penalites_dues(a.id)       AS penalites_dues
    FROM adherent a
   WHERE a.id = p_adherent_id;

  -- 2) ses emprunts en cours
  SELECT em.id AS emprunt_id, o.titre, ex.code_barre,
         em.date_emprunt, em.date_retour_prevue,
         f_jours_de_retard(em.id) AS jours_retard
    FROM emprunt em
    JOIN exemplaire ex ON ex.id = em.exemplaire_id
    JOIN ouvrage    o  ON o.id  = ex.ouvrage_id
   WHERE em.adherent_id = p_adherent_id
     AND em.date_retour_reelle IS NULL;

  -- 3) son nombre total d'emprunts depuis l'inscription
  SELECT COUNT(*) AS nb_emprunts_total
    FROM emprunt
   WHERE adherent_id = p_adherent_id;
END$$
DELIMITER ;

SHOW PROCEDURE STATUS WHERE Db = 'mediatheque';
