-- =====================================================================
--  TP1 - Securiser la base de la mediatheque
--  Rejouable du debut a la fin (a executer en root) :
--      Get-Content -Raw .\01-roles-et-comptes.sql | mysql -u root -p
-- =====================================================================

USE mediatheque;

-- ---------------------------------------------------------------------
--  0. Nettoyage (permet de rejouer le script)
--     Un compte = 'nom'@'machine' : on vise toujours les deux parties.
-- ---------------------------------------------------------------------
DROP USER IF EXISTS 'app_media'@'localhost';
DROP USER IF EXISTS 'biblio_marie'@'localhost';
DROP USER IF EXISTS 'stagiaire'@'localhost';
DROP USER IF EXISTS 'analyste'@'localhost';
DROP USER IF EXISTS 'analyste'@'192.168.1.%';

DROP ROLE IF EXISTS role_catalogue;
DROP ROLE IF EXISTS role_prets;
DROP ROLE IF EXISTS role_adherents;

-- ---------------------------------------------------------------------
--  1. Les trois roles (un role = un metier)
-- ---------------------------------------------------------------------
CREATE ROLE role_catalogue;
CREATE ROLE role_prets;
CREATE ROLE role_adherents;

-- role_catalogue : lecture du catalogue
GRANT SELECT ON mediatheque.ouvrage    TO role_catalogue;
GRANT SELECT ON mediatheque.exemplaire TO role_catalogue;
GRANT SELECT ON mediatheque.categorie  TO role_catalogue;

-- role_prets : circulation des documents (jamais de DELETE)
GRANT SELECT, INSERT, UPDATE ON mediatheque.emprunt     TO role_prets;
GRANT SELECT, INSERT, UPDATE ON mediatheque.reservation TO role_prets;
GRANT SELECT, INSERT, UPDATE ON mediatheque.penalite    TO role_prets;
-- Privilege de COLONNE : seule la colonne "disponible" est modifiable
GRANT UPDATE (disponible) ON mediatheque.exemplaire     TO role_prets;

-- role_adherents : gestion des dossiers d'adherents (pas de DELETE : actif = 0)
GRANT SELECT, INSERT, UPDATE ON mediatheque.adherent TO role_adherents;

-- ---------------------------------------------------------------------
--  2. Les quatre comptes (tous en @'localhost')
-- ---------------------------------------------------------------------
CREATE USER 'app_media'@'localhost'    IDENTIFIED BY 'App#Media2026';
CREATE USER 'biblio_marie'@'localhost' IDENTIFIED BY 'Marie#Biblio2026';
CREATE USER 'stagiaire'@'localhost'    IDENTIFIED BY 'Stage#Medi2026';
CREATE USER 'analyste'@'localhost'     IDENTIFIED BY 'Analyse#Stat2026';

-- Affectation des roles
GRANT role_catalogue, role_prets                   TO 'app_media'@'localhost';
GRANT role_catalogue, role_prets, role_adherents   TO 'biblio_marie'@'localhost';
GRANT role_catalogue                               TO 'stagiaire'@'localhost';
GRANT role_catalogue                               TO 'analyste'@'localhost';

-- analyste : lit les emprunts (statistiques). On ne lui donne PAS role_prets
-- car ce role porte INSERT/UPDATE : un SELECT direct suffit.
GRANT SELECT ON mediatheque.emprunt TO 'analyste'@'localhost';

-- app_media : uniquement id, nom, prenom, actif de la table adherent
GRANT SELECT (id, nom, prenom, actif) ON mediatheque.adherent TO 'app_media'@'localhost';

-- stagiaire : adherent SANS email, telephone, date_naissance
GRANT SELECT (id, nom, prenom, ville, date_inscription, actif)
  ON mediatheque.adherent TO 'stagiaire'@'localhost';

-- Roles actifs a CHAQUE connexion (sans SET ROLE manuel)
SET DEFAULT ROLE ALL TO
  'app_media'@'localhost',
  'biblio_marie'@'localhost',
  'stagiaire'@'localhost',
  'analyste'@'localhost';

-- ---------------------------------------------------------------------
--  3. Relire les droits
-- ---------------------------------------------------------------------
SHOW GRANTS FOR 'app_media'@'localhost'    USING role_catalogue, role_prets;
SHOW GRANTS FOR 'biblio_marie'@'localhost' USING role_catalogue, role_prets, role_adherents;
SHOW GRANTS FOR 'stagiaire'@'localhost'    USING role_catalogue;
SHOW GRANTS FOR 'analyste'@'localhost'     USING role_catalogue;

SELECT grantee, table_name, column_name, privilege_type
  FROM information_schema.column_privileges
 WHERE table_schema = 'mediatheque'
 ORDER BY grantee, table_name, column_name;

-- Cycle complet GRANT -> verification -> REVOKE -> verification
-- (l'analyste n'a finalement pas besoin des reservations)
GRANT SELECT ON mediatheque.reservation TO 'analyste'@'localhost';
SHOW GRANTS FOR 'analyste'@'localhost';
REVOKE SELECT ON mediatheque.reservation FROM 'analyste'@'localhost';
SHOW GRANTS FOR 'analyste'@'localhost';

-- ---------------------------------------------------------------------
--  5. BONUS
-- ---------------------------------------------------------------------
-- Analyste depuis le reseau 192.168.1.x, memes privileges
CREATE USER 'analyste'@'192.168.1.%' IDENTIFIED BY 'Analyse#Reseau2026';
GRANT role_catalogue TO 'analyste'@'192.168.1.%';
GRANT SELECT ON mediatheque.emprunt TO 'analyste'@'192.168.1.%';
SET DEFAULT ROLE ALL TO 'analyste'@'192.168.1.%';

-- Si 'analyste'@'%' existait aussi : pour une connexion depuis 192.168.1.20,
-- MySQL choisit le compte dont l'hote est le PLUS SPECIFIQUE, donc
-- 'analyste'@'192.168.1.%' passerait avant 'analyste'@'%'. Les deux comptes
-- sont independants (mots de passe et droits differents) : si l'on se trompe
-- de mot de passe pour le compte specifique, MySQL ne bascule pas sur '%'.
-- Un '%' ouvre en outre le compte a tout Internet : a eviter.

-- Fin de stage, deux commandes possibles pour 'stagiaire' :
--   ALTER USER 'stagiaire'@'localhost' ACCOUNT LOCK;   -- reversible, droits conserves
--   DROP USER 'stagiaire'@'localhost';                 -- definitif
-- Choix : ALTER USER ... ACCOUNT LOCK le jour de la fin de stage (connexion
-- impossible immediatement, reversible si le stage est prolonge ou en cas
-- d'erreur), puis DROP USER apres quelques semaines une fois que plus rien
-- (ex. objets dependants, journaux) ne reference le compte.
