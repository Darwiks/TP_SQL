-- =====================================================================
--  TP3 - Table d'audit et triggers sur emprunt
--  A executer en root, APRES 01-fonctions.sql :
--      Get-Content -Raw .\03-triggers.sql | mysql -u root -p mediatheque -t
--  Rejouable : DROP TRIGGER IF EXISTS avant chaque CREATE.
--
--  Regle du TP : un INVARIANT de donnees va dans un trigger.
--  Pas d'accents dans les textes (PowerShell les abime en envoyant le fichier).
-- =====================================================================

USE mediatheque;

-- ---------------------------------------------------------------------
-- Table d'audit
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- 1) BEFORE INSERT : le pret dure 14 jours (valeur calculee) et les dates
--    doivent etre coherentes. En BEFORE on modifie la ligne avec
--    SET NEW.colonne, jamais avec un UPDATE sur la table elle-meme.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_emprunt_bi;
DELIMITER $$
CREATE TRIGGER trg_emprunt_bi
BEFORE INSERT ON emprunt
FOR EACH ROW
BEGIN
  IF NEW.date_emprunt IS NULL THEN
    SET NEW.date_emprunt = CURDATE();
  END IF;

  IF NEW.date_retour_prevue IS NULL THEN
    SET NEW.date_retour_prevue = NEW.date_emprunt + INTERVAL 14 DAY;
  END IF;

  IF NEW.date_retour_prevue < NEW.date_emprunt
     OR (NEW.date_retour_reelle IS NOT NULL
         AND NEW.date_retour_reelle < NEW.date_emprunt) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Date de retour anterieure a la date d emprunt.';
  END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 2) AFTER INSERT : un exemplaire sorti n'est pas disponible (invariant)
--    + trace dans le journal.
--    "auteur" = USER() (la personne connectee). CURRENT_USER() renverrait
--    le DEFINER du trigger, donc toujours le meme compte.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_emprunt_ai;
DELIMITER $$
CREATE TRIGGER trg_emprunt_ai
AFTER INSERT ON emprunt
FOR EACH ROW
BEGIN
  UPDATE exemplaire SET disponible = 0 WHERE id = NEW.exemplaire_id;

  INSERT INTO journal_action (table_cible, operation, cle, auteur, horodatage, details)
  VALUES ('emprunt', 'INSERT', NEW.id, USER(), NOW(),
          CONCAT('exemplaire ', NEW.exemplaire_id,
                 ', adherent ', NEW.adherent_id,
                 ', retour prevu le ', NEW.date_retour_prevue));
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3) AFTER UPDATE : on detecte le PASSAGE de date_retour_reelle de NULL
--    a une date (OLD / NEW). Sans cette comparaison, n'importe quelle
--    modification de la ligne (meme un simple changement de date)
--    rendrait l'exemplaire disponible alors qu'il est encore chez l'adherent.
--    Toute ecriture sur emprunt est journalisee : le ELSE trace les autres UPDATE.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_emprunt_au;
DELIMITER $$
CREATE TRIGGER trg_emprunt_au
AFTER UPDATE ON emprunt
FOR EACH ROW
BEGIN
  IF OLD.date_retour_reelle IS NULL AND NEW.date_retour_reelle IS NOT NULL THEN
    UPDATE exemplaire SET disponible = 1 WHERE id = NEW.exemplaire_id;

    INSERT INTO journal_action (table_cible, operation, cle, auteur, horodatage, details)
    VALUES ('emprunt', 'UPDATE', NEW.id, USER(), NOW(),
            CONCAT('retour enregistre le ', NEW.date_retour_reelle));
  ELSE
    INSERT INTO journal_action (table_cible, operation, cle, auteur, horodatage, details)
    VALUES ('emprunt', 'UPDATE', NEW.id, USER(), NOW(),
            'modification sans retour');
  END IF;
END$$
DELIMITER ;

-- Verification : trois triggers attendus
SHOW TRIGGERS FROM mediatheque;
